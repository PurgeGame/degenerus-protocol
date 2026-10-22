// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {GameSlots} from "../../helpers/GameSlots.sol";

import {console} from "forge-std/console.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DegenesisDeployProtocol} from "../helpers/DeployProtocol.sol";
import {DegenesisLivenessHandler} from "../handlers/DegenesisLivenessHandler.sol";

/// @title DegenesisLiveness -- mineFlip never stalls across the Degenesis sale
/// @notice Deploys on day index 1 with the sale ahead. The handler mixes every buy type, the
///         Vault's budget spend, VRF delays and stalls (one across the close) and mineFlip calls
///         at gas drawn from the first action's minimum admission upward. Invariant: every call
///         either progressed or reported exactly what the engine's selector said (NoWork when
///         idle, RngNotReady when waiting); none reverted otherwise. After each run, with VRF
///         answering, the game must leave the sale, close all seven cohorts and reach level 1.
contract DegenesisLiveness is DegenesisDeployProtocol {
    DegenesisLivenessHandler public handler;

    function setUp() public {
        _deployProtocol();
        vm.deal(address(game), 100_000 ether);
        mockVRF.fundSubscription(1, 1_000_000 ether);
        handler = new DegenesisLivenessHandler(game, mockVRF, 12);
        targetContract(address(handler));

        bytes4[] memory sels = new bytes4[](21);
        sels[0] = DegenesisLivenessHandler.actBuyTickets.selector;
        sels[1] = DegenesisLivenessHandler.actBuyLootbox.selector;
        sels[2] = DegenesisLivenessHandler.actFoil.selector;
        sels[3] = DegenesisLivenessHandler.actWhalePass.selector;
        sels[4] = DegenesisLivenessHandler.actBuyDegenesis.selector;
        sels[5] = DegenesisLivenessHandler.actBuyDegenesis.selector;
        sels[6] = DegenesisLivenessHandler.actVaultSpend.selector;
        sels[7] = DegenesisLivenessHandler.actSeedPool.selector;
        sels[8] = DegenesisLivenessHandler.actFulfill.selector;
        sels[9] = DegenesisLivenessHandler.actDelayedFulfill.selector;
        sels[10] = DegenesisLivenessHandler.actStall.selector;
        sels[11] = DegenesisLivenessHandler.actNextDay.selector;
        sels[12] = DegenesisLivenessHandler.actNextDay.selector;
        sels[13] = DegenesisLivenessHandler.actMine.selector;
        sels[14] = DegenesisLivenessHandler.actMine.selector;
        sels[15] = DegenesisLivenessHandler.actMine.selector;
        sels[16] = DegenesisLivenessHandler.actRunToIdle.selector;
        sels[17] = DegenesisLivenessHandler.actBuyDegenesis.selector;
        sels[18] = DegenesisLivenessHandler.actMineTight.selector;
        sels[19] = DegenesisLivenessHandler.actMineTight.selector;
        sels[20] = DegenesisLivenessHandler.actFlipPaidTickets.selector;
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: sels}));
    }

    /// forge-config: default.invariant.runs = 32
    /// forge-config: default.invariant.depth = 60
    /// forge-config: deep.invariant.runs = 256
    /// forge-config: deep.invariant.depth = 120
    function invariant_mineFlipProgressesOrReportsIdle() public view {
        if (handler.ghost_violations() == 0) return;
        DegenesisLivenessHandler.Violation memory v = handler.firstViolation();
        _log(v);
        revert(string.concat("mineFlip liveness violation, action ", vm.toString(uint256(v.action))));
    }

    /// @notice Completion and non-vacuity. Coverage accumulates across runs in the process
    ///         environment (the only state that survives each run's setUp).
    function afterInvariant() public {
        handler.finish(uint256(keccak256(abi.encode(block.timestamp, handler.ghost_actions()))));
        if (handler.ghost_violations() != 0) _log(handler.firstViolation());
        if (!handler.finishSettled() || handler.finishLevel() == 0 || !handler.finishLeftSale()) {
            console.log("=== COMPLETION FAILURE ===");
            console.log("trace", handler.trace());
            console.log("day", uint256(game.currentDayView()));
            console.log("level", uint256(game.level()));
            console.log("gameOver", game.gameOver());
            console.log("closed", uint256(uint8(uint256(vm.load(address(game), bytes32(0))) >> 216)));
            console.logBytes32(vm.load(address(game), bytes32(GameSlots.DEGENESIS_ACTIVE)));
            console.logBytes32(vm.load(address(game), bytes32(GameSlots.DEGENESIS_WORD)));
            console.log("nextMinerAction", uint256(game.nextMinerAction()));
            console.log("rngLocked", game.rngLocked());
            console.log("liveness fired on day", uint256(handler.finishLivenessDay()));
            console.logBytes32(bytes32(handler.finishLivenessSlot0()));
            console.log("last VRF request", mockVRF.lastRequestId());
        }
        assertEq(handler.ghost_violations(), 0, "mineFlip liveness violation during completion");
        assertTrue(handler.finishLeftSale(), "the game left the sale");
        assertTrue(handler.finishSettled(), "all seven Degenesis cohorts closed");
        assertGe(uint256(handler.finishLevel()), 1, "the game reached level 1");

        string[25] memory keys = [
            "belowMinOtherReverts", "flipBuys", "tightSteps", "runs", "mineCalls", "mineProgress", "noWork", "rngNotReady", "minGasCalls", "settleCalls",
            "saleRequests", "saleApplies", "degenesisBuys", "degenesisMinBuys", "degenesisAfkingBuys",
            "vaultSpends", "bigBoxBuys", "whaleBuys", "splits", "priced", "resolved", "burns", "stalls",
            "stallOverClose", "gapDays"
        ];
        uint256[25] memory vals = [
            handler.ghost_belowMinOtherReverts(), handler.ghost_flipBuys(), handler.ghost_tightSteps(), uint256(1), handler.ghost_mineCalls(), handler.ghost_mineProgress(), handler.ghost_noWork(),
            handler.ghost_rngNotReady(), handler.ghost_minGasCalls(), handler.ghost_settleCalls(),
            handler.ghost_saleRequests(), handler.ghost_saleApplies(), handler.ghost_degenesisBuys(),
            handler.ghost_degenesisMinBuys(), handler.ghost_degenesisAfkingBuys(), handler.ghost_vaultSpends(),
            handler.ghost_bigBoxBuys(), handler.ghost_whaleBuys(), handler.ghost_splits(), handler.ghost_priced(),
            handler.ghost_resolved(), handler.ghost_burns(), handler.ghost_stalls(), handler.ghost_stallOverClose(),
            handler.ghost_gapDays()
        ];
        string memory line = "DEGENESIS_LIVENESS_COVERAGE";
        for (uint256 i; i < keys.length; ++i) {
            string memory k = string.concat("DGL_COV_", keys[i]);
            uint256 acc = vm.envOr(k, uint256(0)) + vals[i];
            vm.setEnv(k, vm.toString(acc));
            line = string.concat(line, " ", keys[i], "=", vm.toString(acc));
        }
        console.log(line);
        console.log(string.concat("DEGENESIS_LIVENESS_RUN finishDays=", vm.toString(handler.finishDays()),
            " level=", vm.toString(uint256(handler.finishLevel())), " actions=", vm.toString(handler.ghost_actions())));

        // Every run reaches the seventh close through finish alone.
        assertGt(handler.ghost_burns(), 0, "vacuous: the leftover inventory never burned");
        uint256 runs = vm.envOr("DGL_COV_runs", uint256(0));
        if (runs < 8) return;
        string[16] memory required = [
            "whaleBuys", "saleRequests", "tightSteps", "settleCalls", "minGasCalls", "noWork", "rngNotReady", "degenesisBuys", "degenesisMinBuys", "degenesisAfkingBuys",
            "vaultSpends", "bigBoxBuys", "splits", "resolved", "stalls", "saleApplies"
        ];
        for (uint256 i; i < required.length; ++i) {
            assertGt(vm.envOr(string.concat("DGL_COV_", required[i]), uint256(0)), 0,
                string.concat("vacuous: never reached ", required[i]));
        }
        if (runs < 24) return;
        assertGt(vm.envOr("DGL_COV_stallOverClose", uint256(0)), 0, "vacuous: never stalled across the close");
        assertGt(vm.envOr("DGL_COV_gapDays", uint256(0)), 0, "vacuous: never skipped a day");
        assertGt(vm.envOr("DGL_COV_flipBuys", uint256(0)), 0, "vacuous: never bought FLIP-paid tickets");
    }

    /// @notice Every handler action runs (none reverts) along one deterministic sale.
    function test_HandlerActionsRun() public {
        for (uint256 d; d < 9; ++d) {
            handler.actBuyTickets(d, 5);
            handler.actBuyLootbox(d, d, 3, 1_000);
            handler.actBuyDegenesis(d, d, d);
            handler.actFoil(d);
            handler.actWhalePass(d, 2);
            handler.actVaultSpend(800, 1);
            handler.actMine(d, 4, d);
            handler.actFulfill();
            handler.actRunToIdle(d);
            handler.actNextDay(1 hours, 0);
        }
        handler.actStall(1, 0);
        handler.actDelayedFulfill(1 hours);
        handler.actSeedPool(0);
        handler.actMineTight(1, 4, 7);
        handler.actFlipPaidTickets(2, 5);
        assertEq(handler.ghost_actions(), 9 * 10 + 5, "every action ran");
        handler.finish(1);
        if (handler.ghost_violations() != 0) _log(handler.firstViolation());
        assertEq(handler.ghost_violations(), 0, "no violation");
        assertTrue(handler.finishSettled(), "settled");
        assertGe(uint256(handler.finishLevel()), 1, "level 1");
        assertGt(handler.ghost_degenesisBuys(), 0, "Degenesis buys");
        assertGt(handler.ghost_whaleBuys(), 0, "whale buys");
        assertGt(handler.ghost_resolved(), 0, "orders resolved");
    }

    function _log(DegenesisLivenessHandler.Violation memory v) internal pure {
        console.log("=== DEGENESIS LIVENESS VIOLATION ===");
        console.log("action", uint256(v.action));
        console.logBytes4(v.selector);
        console.log("gas given", v.gasGiven);
        console.log("min gas", v.minGas);
        console.log("day", uint256(v.day));
        console.log("level", uint256(v.level));
        console.log("degenesisClosed", uint256(v.degenesisClosed));
        console.log("actionNo", v.actionNo);
        console.log("where", v.where);
    }
}
