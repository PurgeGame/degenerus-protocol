// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {DegenesisWeekOpening} from "../helpers/DegenesisWeekOpening.sol";
import {CompositionHandler} from "../handlers/CompositionHandler.sol";
import {CompositionInvariant} from "./Composition.inv.t.sol";
import {GameSlots} from "../../helpers/GameSlots.sol";

/// @title CompositionDegenesis -- cross-module composition after a real Degenesis week (turbo launch)
/// @notice Purchase, whale, advance-cycle and day-warp sequences on the game the sale left: level 1 after
///         its turbo jackpot, the Vault budget and sDGNRS AFKing funded by the splits. Adds: nothing
///         reopens the sale.
contract CompositionDegenesis is CompositionInvariant, DegenesisWeekOpening {
    function _deployTimestamp() internal pure override(DeployProtocol, DegenesisWeekOpening) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    function setUp() public override {
        _deployProtocol();
        _degenesisWeek(true);
        compositionHandler = new CompositionHandler(game, mockVRF, 8);
        targetContract(address(compositionHandler));
    }

    function invariant_degenesisSaleStaysClosed() public view {
        _assertSaleStaysClosed();
    }

    function test_degenesisWeekHappened() public view {
        _assertDegenesisWeekHappened();
    }
}

/// @title CompositionDegenesisBacklog -- the same, handed off with the Degenesis settlement backlog open
/// @notice Cohort 6 is mid-settlement and cohort 7 split but unpriced when the composition campaign
///         starts, so purchases, whale buys, advance cycles and day warps interleave with the backlog's
///         settlement, its pricing at a later request and the seventh close with its burn.
contract CompositionDegenesisBacklog is CompositionInvariant, DegenesisWeekOpening {
    function _deployTimestamp() internal pure override(DeployProtocol, DegenesisWeekOpening) returns (uint256) {
        return DEPLOY_TS_DEGENESIS;
    }

    function _dgwBacklog() internal pure override returns (bool) {
        return true;
    }

    function setUp() public override {
        _deployProtocol();
        _degenesisWeek(true);
        compositionHandler = new CompositionHandler(game, mockVRF, 8);
        targetContract(address(compositionHandler));
    }

    function invariant_degenesisBacklogSettlesForward() public view {
        _assertBacklogSettlesForward();
    }

    function test_degenesisWeekHappened() public view {
        _assertDegenesisWeekHappened();
    }

    /// @notice From the hand-off, ordinary days drain the backlog: every remaining order resolves
    ///         exactly once, cohort 7 prices at a later request and closes, and the inventory burns.
    function test_backlogDrainsUnderOrdinaryDays() public {
        uint24 d = game.currentDayView_g542950();
        while (_dgwClosed() < 7) {
            ++d;
            require(d <= dgw.endDay + 5, "backlog never drained");
            _dgwWarp(d, 1 hours);
            _dgwDrive();
        }
        assertEq(dgw.resolved, dgw.orders, "every order resolved exactly once");
        assertEq(dgw.priced, 7, "seven cohorts priced");
        assertEq(dgw.closed, 7, "seven closes");
        assertEq(dgw.burns, 1, "one burn");
        _assertBacklogSettlesForward();
    }

    /// @notice A liveness ending with the backlog open forfeits the unresolved orders: terminal setup
    ///         splits nothing new (all seven split), zeroes the active cohort, and the miner never
    ///         reaches Degenesis settlement again, though the bound word stays behind as dead storage.
    ///         Every terminal call, through the final sweep 30 days later, succeeds or reports no
    ///         work; the Game stays solvent.
    function test_livenessEndingDuringBacklogForfeitsAndNeverSettles() public {
        uint8 closed0 = _dgwClosed();
        uint256 resolved0 = dgw.resolved;
        vm.warp(vm.getBlockTimestamp() + 31 days);
        assertTrue(game.livenessTriggered(), "fixture: deadman");
        for (uint256 i; i < 400 && !game.gameOver(); ++i) {
            _dgwFulfil();
            assertTrue(game.nextMinerAction() != DGW_ACTION_SETTLE, "settlement offered during the ending");
            game.mineRun(0);
        }
        assertTrue(game.gameOver(), "game over");
        _dgwScan();
        assertEq(dgw.resolved, resolved0, "no forfeited order paid");
        assertEq(_dgwClosed(), closed0, "no cohort closed by the ending");
        assertEq(uint256(vm.load(address(game), bytes32(GameSlots.DEGENESIS_ACTIVE))), 0, "active cohort forfeited");
        vm.warp(vm.getBlockTimestamp() + 31 days);
        for (uint256 i; i < 400; ++i) {
            _dgwFulfil();
            uint8 a = game.nextMinerAction();
            assertTrue(a != DGW_ACTION_SETTLE, "settlement offered after game over");
            if (a == DGW_ACTION_IDLE) break;
            game.mineRun(0);
        }
        assertEq(game.nextMinerAction(), DGW_ACTION_IDLE, "the ending finished");
        assertGe(address(game).balance + mockStETH.balanceOf(address(game)), game.claimablePoolView(), "solvent after the sweep");
    }
}
