// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {console} from "forge-std/console.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {AdvanceLivenessHandler} from "../handlers/AdvanceLivenessHandler.sol";

/// @title AdvanceLiveness — no "flag set, no work, every entry point reverts" state.
///
/// @notice From ANY fuzzed state, with VRF cooperating and without moving time, mineFlip
///         calls capped at 15M execution gas, each writing engine state, within a per-daily-cycle
///         call budget and at most two logical-day moves, must reach a sealed, idle day: terminal revert
///         NoWork (the engine idle signal), today's word recorded, rng unlocked, the mid-day latch clear, nothing
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

    /// Keep the quick default campaign: each step runs a snapshot-isolated liveness check
    /// (a few hundred bounded cranks plus a craps-probe cycle), so 64 x 100 already takes minutes.
    /// Inline default settings override the inherited deep profile too; explicitly restore
    /// deep's full 1000 x 256 campaign here and verify the executed run/call totals.
    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 100
    /// forge-config: deep.invariant.runs = 1000
    /// forge-config: deep.invariant.depth = 256
    /// CI uses ten distinct seeds; each process still crosses every coverage threshold.
    /// forge-config: deep_advance_ci.invariant.runs = 100
    /// forge-config: deep_advance_ci.invariant.depth = 256
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

        // Non-vacuity. Coverage is accumulated (above) because one run can legitimately miss a shape.
        // Measured over 65 default-profile runs (accumulated totals): checks 7,587, next-day checks 1,499,
        // probe requests 6,918, probe on a last purchase day 319, probe with a frozen pool 22, lpd seals
        // 185 (turbo 56, normal 129), level transitions 916, x9 levels 60, x0 levels 27, mid-day requests
        // 332 (latch set 201, on a last purchase day 183), VRF stalls 100 (daily 44, mid-day 56), foil buys
        // 400 (pending at mid-day 181), biased compound reaching the last purchase day 232. Shapes seen at
        // >= 1 per run are required from 16 runs; the rarer ones (x0 levels, probe with a frozen pool,
        // daily stalls) from 48 runs. middayLatchOnLpdFrozenPool (3 in 65 runs) is too rare to require.
        uint256 runs = vm.envOr("LIVE_COV_runs", uint256(0));
        if (runs < 16) return;
        string[15] memory common = [
            "checks", "nextDayChecks", "probeRequests", "probeOnLpd", "lpdSeals", "turboSeals", "normalSeals",
            "levelTransitions", "x9Levels", "middayRequests", "middayLatchSet", "middayLatchOnLpd", "vrfStallsMidday",
            "foilBuys", "biasedReachedLpd"
        ];
        for (uint256 i; i < common.length; ++i) {
            assertGt(vm.envOr(string.concat("LIVE_COV_", common[i]), uint256(0)), 0,
                string.concat("vacuous: liveness coverage never reached ", common[i]));
        }
        assertGt(vm.envOr("LIVE_COV_foilPendingMidday", uint256(0)), 0, "vacuous: liveness coverage never reached foilPendingMidday");
        if (runs < 48) return;
        string[3] memory rare = ["x0Levels", "probeOnLpdFrozenPool", "vrfStallsDaily"];
        for (uint256 i; i < rare.length; ++i) {
            assertGt(vm.envOr(string.concat("LIVE_COV_", rare[i]), uint256(0)), 0,
                string.concat("vacuous: liveness coverage never reached ", rare[i]));
        }
    }

    /// The liveness probe must actually request and finish a mid-day cycle.
    function test_donorProbeRequestsMidday() public {
        handler.actRunToIdle(0);
        assertEq(handler.ghost_violations(), 0, "liveness violation in donor probe");
        assertGt(handler.ghost_probeRequests(), 0, "donor probe must issue a request");
    }

    /// @dev The unshrunk 20-action campaign counterexample (the shrinker's one-call version did
    ///      not reproduce). Its next-day check works through two daily cycles, which the former
    ///      flat 250-call cutoff (one direct coin-ticket round per call, 280 calls) misread as
    ///      nontermination. Typed calls make any handler revert fail the replay instead of
    ///      passing silently.
    function test_BackloggedTicketJackpotStillReachesIdle() public {
        AdvanceLivenessHandler h = handler;
        h.actFulfill();
        h.actFulfill();
        h.actBuyTickets(987973558385376108849394590885168956720493512112609995, 1935583008242558388719462530735388318471);
        h.actMiddayRequest(9970, 900);
        h.actSeedPool(1874555648000875330519283469014130688475938277111934308827207);
        h.actMiddayRequest(30796461393168801175815566740, 340949541655144437384211277808400785192);
        h.actNextDay(41299094766155748286151641988568637358933361195574772186612623152482089, 2625);
        h.actFulfill();
        h.actLastPurchaseDayMidday(838577680921497);
        h.actWhalePass(2931);
        h.actNextDay(59, 100000);
        h.actFulfill();
        h.actNextDay(12760, 70288520262548602561809328627061950964226901219486286149240540285536414457052);
        h.actBuyTickets(238820929411270246290542585567, 1031759998269520168895688991388934435654640608096489774789269293622877549);
        h.actStall(73274681686168728259960734043533118148390246983530491227646187673309033888016);
        h.actWarpWithinDay(73274681686168728259960734043533118148390246983530491227646187673309033815728);
        h.actStall(1329828);
        h.actCrank(7249676749272314, 2656675073431816517);
        h.actFulfill();
        h.actFulfill();
        if (h.ghost_violations() != 0) _logViolation(h.firstViolation());
        assertEq(h.ghost_violations(), 0, "backlogged jackpot must reach idle");
        assertEq(h.ghost_actions(), 20, "every replayed action ran");
        assertEq(h.ghost_nextDayChecks(), 5, "every fourth action ran its next-day check");
        assertEq(h.ghost_maxDayAdvances(), 1, "non-vacuity: that check spanned two daily cycles");
        assertLe(h.ghost_maxCranksPerCycle(), h.MAX_CRANKS_PER_CYCLE());
        console.log("backlog max cranks", h.ghost_maxCranks());
        console.log("backlog max cranks per cycle", h.ghost_maxCranksPerCycle());
    }

    /// @dev Oracle self-check: a mineFlip that succeeds without writing engine state is flagged
    ///      at once rather than consuming the cycle budget.
    function test_OracleFlagsSuccessWithoutProgress() public {
        vm.mockCall(address(game), abi.encodeWithSignature("mineRun(uint32)", uint32(0)), "");
        handler.actFulfill();
        assertEq(handler.ghost_violations(), 1);
        assertEq(handler.firstViolation().code, handler.V_NO_PROGRESS());
        assertEq(handler.firstViolation().cranks, 1);
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
        console.log("code (1 noQuiesce,2 terminalRevert,3 latchStuck,4 notSealed,5 stagedNoWorker,6 advanceDueLies,7 requestBlocked,8 noProgress)", uint256(v.code));
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
