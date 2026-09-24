// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {AdvanceLivenessHandler} from "../handlers/AdvanceLivenessHandler.sol";

/// @title AdvanceLiveness — no "flag set, no work, every entry point reverts" state.
///
/// @notice From ANY fuzzed state, with VRF cooperating and without moving time, a bounded
///         number of advanceGame cranks must reach a sealed, idle day: terminal revert
///         NotTimeYet, today's word recorded, rng unlocked, the mid-day latch clear, nothing
///         staged without a worker (ticketsFullyProcessed), advanceDue() consistent, and a
///         mid-day lootbox request not blocked by MidDayActive. A CRAPS-table probe request
///         (exempt from the pending-value gates) plus fulfil + cranks must return to the same
///         idle state, and every Kth step the next day must seal. See AdvanceLivenessHandler.
contract AdvanceLiveness is DeployProtocol {
    AdvanceLivenessHandler public handler;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 100_000 ether);
        // LINK floor for mid-day / craps requests (admin ctor creates subId 1)
        mockVRF.fundSubscription(1, 1_000_000 ether);

        handler = new AdvanceLivenessHandler(game, mockVRF, 16);
        targetContract(address(handler));

        bytes4[] memory sels = new bytes4[](16);
        sels[0] = AdvanceLivenessHandler.actBuyTickets.selector;
        sels[1] = AdvanceLivenessHandler.actBuyLootbox.selector;
        sels[2] = AdvanceLivenessHandler.actFoil.selector;
        sels[3] = AdvanceLivenessHandler.actWhalePass.selector;
        sels[4] = AdvanceLivenessHandler.actOpenBoxes.selector;
        sels[5] = AdvanceLivenessHandler.actMiddayRequest.selector;
        sels[6] = AdvanceLivenessHandler.actFulfill.selector;
        sels[7] = AdvanceLivenessHandler.actCrank.selector;
        sels[8] = AdvanceLivenessHandler.actRunToIdle.selector;
        sels[9] = AdvanceLivenessHandler.actWarpWithinDay.selector;
        sels[10] = AdvanceLivenessHandler.actNextDay.selector;
        sels[11] = AdvanceLivenessHandler.actStall.selector;
        sels[12] = AdvanceLivenessHandler.actSeedPool.selector;
        // LIVE_NO_BIAS=true drops the biased compound so only the generic actions + probe run.
        sels[13] = vm.envOr("LIVE_NO_BIAS", false)
            ? AdvanceLivenessHandler.actSeedPool.selector
            : AdvanceLivenessHandler.actLastPurchaseDayMidday.selector;
        // extra weight on the day driver and the mid-day request
        sels[14] = AdvanceLivenessHandler.actNextDay.selector;
        sels[15] = AdvanceLivenessHandler.actMiddayRequest.selector;
        targetSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: sels}));
    }

    /// Pinned below the default profile: each step runs a snapshot-isolated liveness check
    /// (up to 250 cranks plus a craps-probe cycle), so 64 x 100 already takes minutes.
    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 100
    function invariant_advanceLiveness() public view {
        if (handler.ghost_violations() == 0) return;
        AdvanceLivenessHandler.Violation memory v = handler.firstViolation();
        _logViolation(v);
        revert(string.concat("LIVENESS violation code ", vm.toString(uint256(v.code))));
    }

    /// Per-run coverage, accumulated across runs through the process environment
    /// (the only state that survives the per-run setUp).
    function afterInvariant() public {
        string[24] memory keys = [
            "checks",
            "nextDayChecks",
            "probeRequests",
            "probeOnLpd",
            "probeOnLpdFrozenPool",
            "lpdSeals",
            "turboSeals",
            "normalSeals",
            "levelTransitions",
            "x9Levels",
            "x0Levels",
            "maxLevel",
            "middayRequests",
            "middayLatchSet",
            "middayLatchOnLpd",
            "middayLatchOnLpdFrozenPool",
            "vrfStalls",
            "vrfStallsDaily",
            "vrfStallsMidday",
            "foilBuys",
            "foilPendingMidday",
            "biasedReachedLpd",
            "gameOverRuns",
            "runs"
        ];
        uint256[24] memory vals = [
            handler.ghost_checks(),
            handler.ghost_nextDayChecks(),
            handler.ghost_probeRequests(),
            handler.ghost_probeOnLpd(),
            handler.ghost_probeOnLpdFrozenPool(),
            handler.ghost_lpdSeals(),
            handler.ghost_turboSeals(),
            handler.ghost_normalSeals(),
            handler.ghost_levelTransitions(),
            handler.ghost_x9Levels(),
            handler.ghost_x0Levels(),
            handler.ghost_maxLevel(),
            handler.ghost_middayRequests(),
            handler.ghost_middayLatchSet(),
            handler.ghost_middayLatchOnLpd(),
            handler.ghost_middayLatchOnLpdFrozenPool(),
            handler.ghost_vrfStalls(),
            handler.ghost_vrfStallsDaily(),
            handler.ghost_vrfStallsMidday(),
            handler.ghost_foilBuys(),
            handler.ghost_foilPendingMidday(),
            handler.ghost_biasedReachedLpd(),
            game.gameOver() ? 1 : 0,
            1
        ];
        string memory line = "LIVENESS_COVERAGE";
        for (uint256 i = 0; i < 24; i++) {
            string memory k = string.concat("LIVE_COV_", keys[i]);
            uint256 acc = vm.envOr(k, uint256(0));
            // maxLevel is a max, everything else a sum
            acc = i == 11 ? (vals[i] > acc ? vals[i] : acc) : acc + vals[i];
            vm.setEnv(k, vm.toString(acc));
            line = string.concat(line, " ", keys[i], "=", vm.toString(acc));
        }
        console.log(line);
        string memory run = string.concat(
            "LIVENESS_RUN maxCranks=",
            vm.toString(handler.ghost_maxCranks()),
            " actions=",
            vm.toString(handler.ghost_actions()),
            " maxLevel=",
            vm.toString(handler.ghost_maxLevel())
        );
        console.log(run);
    }

    /// Deterministic replay of the biased scenario — a quick regression for the seed bug.
    function test_lastPurchaseDayMiddayScenario() public {
        for (uint256 s = 0; s < 6 && handler.ghost_violations() == 0; s++) {
            handler.actLastPurchaseDayMidday(uint256(keccak256(abi.encode("lpd-midday", s))) & ~uint256(1));
            handler.actNextDay(1 hours, 0);
            handler.actRunToIdle(0);
        }
        console.log("biasedReachedLpd", handler.ghost_biasedReachedLpd());
        console.log("middayLatchOnLpdFrozenPool", handler.ghost_middayLatchOnLpdFrozenPool());
        console.log("probeOnLpdFrozenPool", handler.ghost_probeOnLpdFrozenPool());
        if (handler.ghost_violations() != 0) _logViolation(handler.firstViolation());
        assertEq(handler.ghost_violations(), 0, "liveness violation in the biased scenario");
    }

    function _logViolation(AdvanceLivenessHandler.Violation memory v) internal pure {
        console.log("=== LIVENESS VIOLATION ===");
        console.log("code (1 noQuiesce,2 terminalRevert,3 latchStuck,4 notSealed,5 stagedNoWorker,6 advanceDueLies,7 requestBlocked)", uint256(v.code));
        console.log("phase (0 same-day,1 after CRAPS probe,2 next-day,3 next-day+probe)", uint256(v.phase));
        console.logBytes4(v.selector);
        console.log("cranks", uint256(v.cranks));
        console.log("actionNo", uint256(v.actionNo));
        console.log("lastAction", v.lastAction);
        console.log("level", uint256(v.level));
        console.log("wallDay", uint256(v.wallDay));
        console.log("dailyIdx", uint256(v.dailyIdx));
        console.log("jackpotPhase", v.jackpotPhase);
        console.log("lastPurchaseDay", v.lastPurchaseDay);
        console.log("turbo", v.turbo);
        console.log("rngLocked", v.rngLocked);
        console.log("ticketsFullyProcessed", v.ticketsFullyProcessed);
        console.log("midDayLatch", uint256(v.midDayLatch));
        console.log("rngRequestTime", uint256(v.rngRequestTime));
        console.log("wordToday", uint256(v.wordToday));
        console.log("advanceDue", v.advanceDue);
        console.log("readLen L / L+1 / L+2", v.readLenL, v.readLenL1, v.readLenL2);
        console.log("farFuture len L+1 / L+2", v.ffLenL1, v.ffLenL2);
        console.log("foilPending", v.foilPending);
        console.log("timestamp", uint256(v.timestamp));
    }
}
