// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {GameSlots} from "../../helpers/GameSlots.sol";
import {DegenesisCompletionReplay} from "../../helpers/DegenesisCompletionReplay.sol";

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
///         answering, a healthy game must leave the sale, close all seven cohorts and reach level 1.
///         A trace that exhausts the independent 14-day completion deadline must instead finish
///         its justified deterministic ending. VRF delivery alone does not reset that deadline.
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
        require(!handler.ghost_unjustifiedTerminal(), "unjustified terminal outcome");
        if (handler.ghost_violations() == 0) return;
        DegenesisLivenessHandler.Violation memory v = handler.firstViolation();
        _log(v);
        revert(string.concat("mineFlip liveness violation, action ", vm.toString(uint256(v.action))));
    }

    /// @notice Completion and non-vacuity. Coverage accumulates across runs in the process
    ///         environment (the only state that survives each run's setUp).
    function afterInvariant() public {
        uint256 preFinishActions = handler.ghost_actions();
        handler.finish(uint256(keccak256(abi.encode(block.timestamp, handler.ghost_actions()))));
        if (handler.ghost_violations() != 0) _log(handler.firstViolation());
        if (!handler.finishTerminal()
            && (!handler.finishSettled() || handler.finishLevel() == 0 || !handler.finishLeftSale())) {
            console.log("=== COMPLETION FAILURE ===");
            console.log("trace", handler.trace());
            console.log("day", uint256(game.currentDayView_g542950()));
            console.log("level", uint256(game.currentLvl()));
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
        assertCompletionOutcome();

        string[27] memory keys = [
            "belowMinOtherReverts", "flipBuys", "tightSteps", "runs", "mineCalls", "mineProgress", "noWork", "rngNotReady", "minGasCalls", "settleCalls",
            "saleRequests", "saleApplies", "degenesisBuys", "degenesisMinBuys", "degenesisAfkingBuys",
            "vaultSpends", "bigBoxBuys", "whaleBuys", "splits", "priced", "resolved", "burns", "stalls",
            "stallAcrossReset", "gapDays", "healthyCompletions", "deadlineEndings"
        ];
        uint256[27] memory vals = [
            handler.ghost_belowMinOtherReverts(), handler.ghost_flipBuys(), handler.ghost_tightSteps(), uint256(1), handler.ghost_mineCalls(), handler.ghost_mineProgress(), handler.ghost_noWork(),
            handler.ghost_rngNotReady(), handler.ghost_minGasCalls(), handler.ghost_settleCalls(),
            handler.ghost_saleRequests(), handler.ghost_saleApplies(), handler.ghost_degenesisBuys(),
            handler.ghost_degenesisMinBuys(), handler.ghost_degenesisAfkingBuys(), handler.ghost_vaultSpends(),
            handler.ghost_bigBoxBuys(), handler.ghost_whaleBuys(), handler.ghost_splits(), handler.ghost_priced(),
            handler.ghost_resolved(), handler.ghost_burns(), handler.ghost_stalls(), handler.ghost_stallAcrossReset(),
            handler.ghost_gapDays(), healthyCompletionEligible(preFinishActions) ? uint256(1) : 0,
            handler.finishTerminal() ? uint256(1) : 0
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

        // Only healthy completion closes cohort seven. A justified hard ending forfeits the
        // remaining orders and has its own terminal-work retirement checks above.
        if (!handler.finishTerminal()) {
            assertGt(handler.ghost_burns(), 0, "vacuous: the leftover inventory never burned");
        }
        uint256 runs = vm.envOr("DGL_COV_runs", uint256(0));
        if (runs < 8) return;
        string[17] memory required = [
            "whaleBuys", "saleRequests", "tightSteps", "settleCalls", "minGasCalls", "noWork", "rngNotReady", "degenesisBuys", "degenesisMinBuys", "degenesisAfkingBuys",
            "vaultSpends", "bigBoxBuys", "splits", "resolved", "stalls", "saleApplies", "healthyCompletions"
        ];
        for (uint256 i; i < required.length; ++i) {
            assertGt(vm.envOr(string.concat("DGL_COV_", required[i]), uint256(0)), 0,
                string.concat("vacuous: never reached ", required[i]));
        }
        if (runs < 24) return;
        assertGt(vm.envOr("DGL_COV_stallAcrossReset", uint256(0)), 0, "vacuous: never stalled across an actual reset");
        assertGt(vm.envOr("DGL_COV_gapDays", uint256(0)), 0, "vacuous: never skipped a day");
        assertGt(vm.envOr("DGL_COV_flipBuys", uint256(0)), 0, "vacuous: never bought FLIP-paid tickets");
    }

    /// @dev Zero-action completion must not satisfy random-trace coverage; ordinary
    ///      unit tests likewise must not seed process-wide counters.
    function healthyCompletionEligible(uint256 preFinishActions) public view returns (bool) {
        return preFinishActions != 0 && handler.finishRan() && !handler.finishTerminal()
            && handler.finishLeftSale() && handler.finishSettled() && handler.finishLevel() >= 1;
    }

    /// @dev Also used by negative controls; it does not seed process-wide coverage counters.
    function assertCompletionOutcome() public view {
        require(!handler.ghost_unjustifiedTerminal(), "unjustified terminal outcome");
        require(handler.finishRan(), "completion was not driven");
        if (handler.deadlineObservedAt() != 0) {
            require(!handler.finishStartedHealthy(), "healthy completion exhausted its deadline");
            require(handler.deadlineEvidenceValid(), "invalid completion deadline witness");
            require(handler.finishTerminal() && handler.terminalOutcomeValid(), "terminal work did not finish");
        } else {
            require(!game.gameOver(), "unjustified terminal outcome");
            assertTrue(handler.finishLeftSale(), "the game left the sale");
            assertTrue(handler.finishSettled(), "all seven Degenesis cohorts closed");
            assertGe(uint256(handler.finishLevel()), 1, "the game reached level 1");
        }
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
        uint256 preFinishActions = handler.ghost_actions();
        handler.finish(1);
        if (handler.ghost_violations() != 0) _log(handler.firstViolation());
        assertEq(handler.ghost_violations(), 0, "no violation");
        assertFalse(handler.finishTerminal(), "healthy trace must finish the sale");
        assertTrue(handler.finishLeftSale(), "left sale");
        assertTrue(handler.finishSettled(), "settled");
        assertGe(uint256(handler.finishLevel()), 1, "level 1");
        assertGt(handler.ghost_degenesisBuys(), 0, "Degenesis buys");
        assertGt(handler.ghost_whaleBuys(), 0, "whale buys");
        assertGt(handler.ghost_resolved(), 0, "orders resolved");
        assertCompletionOutcome();
        assertTrue(healthyCompletionEligible(preFinishActions), "actionful healthy trace earns coverage");
    }

    function test_ZeroActionFinishCannotSeedHealthyTraceCoverage() public {
        uint256 preFinishActions = handler.ghost_actions();
        assertEq(preFinishActions, 0);
        handler.finish(17);
        assertCompletionOutcome();
        assertFalse(handler.finishTerminal(), "initial state completes the healthy sale");
        assertEq(handler.ghost_actions(), preFinishActions, "finish cannot create random-action evidence");
        assertFalse(healthyCompletionEligible(preFinishActions), "zero-action hook earns no coverage");
    }

    function test_CompletionDeadlineBoundaryAndTerminalRetirement() public {
        (,, uint48 completed) = game.dailySessionState();
        vm.warp(uint256(completed) + 14 days - 1);
        assertFalse(handler.deadlineDue(), "deadline must not fire one second early");
        assertFalse(game.livenessTriggered(), "production agrees before boundary");
        vm.warp(uint256(completed) + 14 days);
        assertTrue(handler.deadlineDue(), "exact independent deadline");
        handler.finish(17);
        assertGt(handler.terminalFinishCalls(), 0, "real terminal work required");
        assertEq(handler.deadlineObservedAt(), uint256(completed) + 14 days);
        assertEq(handler.deadlineLastCompletedAt(), completed);
        assertTrue(handler.finishTerminal());
        assertEq(handler.ghost_violations(), 0);
        assertCompletionOutcome();
    }

    function test_OracleRejectsPrematureTerminalAndLateExcuse() public {
        uint256 baseline = vm.snapshotState();
        for (uint256 kind; kind < 2; ++kind) {
            uint256 header = uint256(vm.load(address(game), bytes32(0)));
            uint256 mask = kind == 0 ? uint256(1) << (GameSlots.GAME_OVER_OFFSET * 8) : uint256(1) << 253;
            vm.store(address(game), bytes32(0), bytes32(header | mask));
            handler.actFulfill();
            assertTrue(handler.ghost_unjustifiedTerminal(), "early terminal state must persist as a failure");
            vm.warp(block.timestamp + 30 days);
            handler.finish(0);
            vm.expectRevert(bytes("unjustified terminal outcome"));
            this.assertCompletionOutcome();
            assertTrue(vm.revertToState(baseline));
        }
    }

    function test_OracleRejectsMissingTerminalCheckpoint() public {
        (,, uint48 completed) = game.dailySessionState();
        vm.warp(uint256(completed) + 14 days);
        handler.finish(17);
        assertCompletionOutcome();
        uint256 ending = uint256(vm.load(address(game), bytes32(GameSlots.GAME_OVER_STATE_PACKED)));
        vm.store(address(game), bytes32(GameSlots.GAME_OVER_STATE_PACKED), bytes32(ending & ~(uint256(255) << 48)));
        vm.expectRevert(bytes("terminal work did not finish"));
        this.assertCompletionOutcome();
    }

    function test_OracleRejectsStaleCompletionDeadlineWitness() public {
        (,, uint48 completed) = game.dailySessionState();
        vm.warp(uint256(completed) + 14 days);
        handler.finish(17);
        assertCompletionOutcome();
        uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.LAST_DAILY_COMPLETED_AT)));
        uint256 shift = GameSlots.LAST_DAILY_COMPLETED_AT_OFFSET * 8;
        packed = (packed & ~(uint256(type(uint48).max) << shift)) | (uint256(completed + 1) << shift);
        vm.store(address(game), bytes32(GameSlots.LAST_DAILY_COMPLETED_AT), bytes32(packed));
        assertFalse(handler.deadlineEvidenceValid(), "a later completion invalidates the old witness");
        vm.expectRevert(bytes("invalid completion deadline witness"));
        this.assertCompletionOutcome();
    }

    /// @notice Preserved75-action seed0x8ad17020261028 sequence, in ordinary unit-test context.
    ///         Warmth/call boundaries differ from the invariant executor; either complete outcome
    ///         must satisfy its full oracle. The original per-action failure is retained separately.
    ///         Each entry is sender(20 bytes), calldata length(2 bytes), calldata.
    function test_Preserved75ActionSequenceHasValidCompletion() public {
        bytes memory replay =
            hex"00000000000000000000000000000000000010190044741943a000000000000283506c575ae5ecaf6cb89a61d7c5d805c4768cbd5a50a7ab526c00000000000000000000000096a0aea28f97a29e86860be3870e94fc55624b77"
            hex"3d7ebc40af7092e3f1c81f2e996cba5cae2090d700442e66cb8c0000000000000000000000000000000000000044ebf91fa1f8850bd9c1fd8feb0000000000000000000000000000000000000000000000122206185e536ca6f5"
            hex"0000000000000000000000000000000000002947006454c045cf000000000002341c8daa938018352af7773111df0b467772d43cac1369f07b2b0000000000000000000000000000000000000000000000000000002bf10ce30200000000000000000000000010b03eb8efe952b72e95e1005f3e68e7798603a9"
            hex"1d1499e622d69689cdf9004d05ec547d650ff21100442e66cb8c00000000000000000000000000000000000000000000000000000000000000240000000000000000000000000000000000000000000000000354a6ba7a180000"
            hex"2a07706473244bc757e10f2a9e86fb532828afe300845c46162b00000000000000000000000000000000000000000000000001630fa8dd51b52600000000000000000000000ab0966c38acc3d54ed0d0ebd7529defd4ca509e2800000000000000000000000007e8de47248ba27ae50e5cdbc1f8f9c856fabf0700000000000000000008c6e50925d83730a534b3880ca88f17587e2b58116399"
            hex"00000000000000000000000000000000000012e50024c934913e0000000000000000000000000000000000000002d9d4260c214288b0dcbe4bc0"
            hex"40bc94a2438dc935f345e40e8638360110f2ce9500442e66cb8c000000000000000000000000000000000000000000000000000000000001731800000000000000000000000000000000000000000000000000000000000000d6"
            hex"000000000000000000000000000000000000578d00442e66cb8c00000000000000000000000000000000000000000000000000426f78426f6f6e00000000000000000000000000000000000000000000004261665469636b6574"
            hex"96d3f6c20eed2697647f543fe6c08bc2fbf39758006402841e52000000000000000000000000000000000000000000000000000000000006b2ae8b20bb722324387cd340076d5cafb4c9bddf994b9993f435f42926ffe699648f00000000000000000000000000000000000000000000000000000000a11ce000"
            hex"9424d51a154206a5b27ad97bd5fbd9c0b2a0879100442e66cb8c000000000000000000000000000000000000000000000000000000000648319b000000000000000000000000000000000000000000000031b206ff6319953f75"
            hex"83898d1f3c03189ff03b471dd3456908fca4423d006402841e52a2eb3e10cd3eb5d0d758ea844e5eec46c96269c5440f2013ba6f40ae79d85eab00000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000157784c27"
            hex"5919b6a429a6bbbe1f0a1b69492e6f41b3a260220044741943a000cab29dda17e025003a65532bcd6c5bec150b0e115b14180cd6ce4d810d311100000000000000000000000000000000000000000001a0899c34043fc351fca9"
            hex"94dada0be5918b6c808908620389d8781799a99100442e66cb8c000000000000000000000000000000000000000000000000000920d6da757e23000000000502e50e74394085d60b7195261728f472295f466e05659b1edb6397"
            hex"319f48e1f7a9b838d4d7642ea83568b57a549fd30044307556f100000000000000000000000000000000000000000000000000000001702e100b0000000000000000000000000000000003584547370f81aa75ac789eb61082e3"
            hex"796f2974e3c1af763252512dd6d521e9e984726c00444188a63f00000000000000001eb76d83e69462f17022562a6b2aa4d9fecccea54480c807000000000000000000000c3c1f23943671eff4218fc9fff57ced67ef2e2560be"
            hex"0000000000000000000000000000000600014ea00024204309580000000000000000000000000000000000000000cdd3be930ee5789df0f1c744"
            hex"a3a6fc2a8609362a38e75e470a4fedd55b9b7f0a006454c045cfa00000010000000000000000000000000000000000000000000000060002ca2098539777c2f5688a054ee9a414ede580419f096069418473bcfc29a19c4b2fe4a000000100000000000000000000000000000000000000000000000600094aa0"
            hex"600c49a0af438f518cb83a36e3297b69a474bd5b006402841e527a50c3d81288238285bbaadf84d728a4976c46bede194d92254f452d5b16c04500000000000000000000000000000000000000000000000000000000000025fc9a37fbd5e796e9046c2f5f7e29046a230a4ba9ada48a80535ed93a51fec5d0fd"
            hex"0000000000000000000000000000000000000b270004edb9e516"
            hex"de1fbdc1c1a21621425405ed9d39877bb19eca8c006478e290260000000000000000091846786667f8ec75521fee18a5b8a99f06803051e3176e0000000000000000000000000000ff917c2a0a583881aa1d169de99d446c0a6800000000000000000000000000000000000000000000000000000d138d405ad8"
            hex"83898d1f3c03189ff03b471dd3456908fca4423d0004edb9e516"
            hex"a407434a406d3d17456d3c93cc68ea6beb9d9772006478e29026fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd0000000000000000000000000000000000000001124d64570990bd10ca10019800000000000000000000000000000000000000051f53606c65bed23846f59f2c"
            hex"6bd6fc9b2da6386000df673e475ff890916f69f2006478e2902600000000000000000490d9dc925605d8ac6b987f7e040960405435b5a1cfeaa40000000000007ec5c91a766cdd7577ad4bd7dd6f0263d21699bcbbd77759648f00000000000000000000000000000000110397cf49de30e0c7a029b74faa595b"
            hex"03a6a84cd762d9707a21605b548aaab891562aab004463d2f90800000000000000000000000000000000070a203035857ba93d9a09e3f9230185000000000000000000000000000000000000000000002427a3abd641c5a0238a"
            hex"11d27cc5bd85e4ec5e0eef9fb3cc295e19e99ad10024ba98c8c22d16324a3bb06d5c2c2ab04afb8e9104e6f2d7bfce57293a39179b5c11bdbf9b"
            hex"f1b4e91ccbf9dc7a98e1ba74ddbffc5c9e619bd90024ba98c8c2cbe5eb94ee31c6183f3d82fc7ed725908f7d7e2da0ee28e8d5e09973be5efd69"
            hex"493ae61c0efae93fd65dee5a3cbc918f0f37cc590044741943a0000000000000000000000057329872328cf3b6ac5eeac2ed69609f463c635c47ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
            hex"fa6f53ce7db42f0f726e6cb9ec2668c34b1579f6006402841e5200000000000000000000000000000000000000000000000000000000000a82dc866bbef5c271e09fbe331c347ea3c3c3d68d78da7fce7e24146639ed57779aff0000000000000000000000000000000000000000000000000000000000ffffff"
            hex"4e5eec46c96269c5440f2013ba6f40ae79d85d78006454c045cf0000000000000000000000000000000000000000000000000000000000001276000000000000000000003dd46d9533d5e60c7adf97231731f6927d8c42df437a000000000000000000000000000000000000da7850b3eea6c4e73e6bbd6e0448"
            hex"d4bab4dc0591774431dec3f823fc15d18817f16a00444f7c016a0000000000000000000000000000000000000000000000000000000000c0ffee000000000000000000000000000000000000000000000000000000000000030c"
            hex"92a6649fdcc044da968d94202465578a9371c7b1006454c045cf000000000000000000000000000016f854a1e30311cf189c85c694341a9319170000000000562345aa8d74a385d9a57badb3817e01b310b34b417619f41b07ce00000000000000000000000000000000000000000947d70620953e8cd03356eb"
            hex"313030222072783d223132222066696c6c3d2200004463d2f9080000000000000000000000000000000000000000000000000000000080000000a000000100000000000000000000000000000000000000000000000600082e80"
            hex"13aa49bac059d709dd0a18d6bb63290076a702d7002420430958000000035154ec8bf9c8454334e47ce5d2ec49b293191b56147e676ca3f16c48"
            hex"7fa9385be102ac3eac297483dd6233d62b3e149600442e66cb8c000000000000000000000000000000000000000000000000000000000000207fc5c930ca00000000000000000000000000000000000000000000000000000001"
            hex"8cfa3e0fccc94a7118161483c2b165850fab6e8b0044307556f1f265760b2566e5fd44e1901e7ec921c6eec1b9a90074cf0881116567e63e837f2ba9afe0c31d8566f9bcc0fe430c62a86995c53c391311d53a1bcae862cae673"
            hex"95c1d595efa197ef5bb8ab413f33658de985b25f004463d2f9080000000000000000000000000000000c1dad38e6424261cd391779c3ea8540cd000000000000000000000000000001d69ad40bc179aeb438b7504b64665f41ba"
            hex"db25a7b768311de128bbda7b8426c3f9c74f324000444f7c016a00000000000000000000000000000000002b6a0780fa4ed9fc52ab66bc9f74210000000000000000000000000000000000000000000000000000070e7101d956"
            hex"cb48c53a77a284f41bd80010f4689033d5016390006454c045cf00000000000000000000000000000000000000000000000000000000000047e8000000000000000000000000000000000000000000000000000000000003416b00000000000000000000000000000000000000000000000000000000001d7ede"
            hex"6afc743aa4e9d98d0f53ff111996e9817d79d301002420430958332eb6b302770f5f91f406f7acb597d37e29bdecfdc1bebf5b71f79789c2155a"
            hex"212224d2f2d262cd093ee13240ca4873fccbba3c006402841e520000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000019f3654a6802d20b2aa31797ac7000000000014ee5a8c72fcfdf7a008f07b7caad74569babf174cecbced971b24"
            hex"007d0ddd72b9c093b96132a092e5c8730d10556500442e66cb8c000000000000000000000000000000000000000000000000000000000002dca7a000000100000000000000000000000000000000000000000000000600089900"
            hex"e194aa6b80ffd71989dd196c7f84fa624b8d7d5d006402841e5200000000000000000000000de721d145bbaed70640a18b1a8f70d42102b5ec89000000000000000000000000000000000000000000000000000000000be946a5000000000000000000000158b8949d0d71c5c474d50ecc47316b44a28ca39992"
            hex"92a6649fdcc044da968d94202465578a9371c7b1006454c045cfbcf871628f1983295a390f19bd04e30059c38e1c029e3ee86e7b105aef438b66000000000000000000000000000000000000000000000000000000000012750000000000000000000000000000000000000000000000000000000000000045a9"
            hex"3381cd18e2fb4db236bf0525938ab6e43db0440f006478e290260000000000000000000000000000000000000000000000000000000000088ee1000000000000000000000000000000000000000000000000000000000f4e540000000000000000000000000000000000000000000000000000000000000000bc"
            hex"5615deb798bb3e4dfa0139dfa1b3d433cc23b72f00444f7c016a00000000000000000000000000000000000000060000000600000006000000bc00000000000000000000000000000000000000000000000000000000000001c6"
            hex"da5a5adc64c8013d334a0da9e711b364af7a4c2d006402841e5200000006000000060000000600000006000000060000000600000006000002b8a0000001000000000000000000000000000000000000000000000006000b4080acc18944c132502a493d6f3dcbc751d281f72da097412a0f6c47b16891d4523f"
            hex"3aefec7c0d0486cf3d79b0a09f63ab69f52d1086006402841e52000000000000000000000000000000000000000000000000000000000000022f0000000000000000000000000000000000000000000000007279cc8f9d45cde60000000000000000000000000000000000001585bc01659562acd426d5df5b4d"
            hex"e3835aab16c24015d195f197549d4d2e139e3432004463d2f90800000000000000000000000000000000000000000000003462c1786c30ed14dc000000000000000000000000000000000000000000000000000012574daec887"
            hex"e040d38a3cf740cd6a2d38503a7fbf391477277d00242043095800000000000000000000000000000000000000000000000000000364d51a8985"
            hex"000000000000000000000000000000060001d000006402841e5200000000000000000000000000000a5aef1e00489503b446995de1353bf10bd200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000ed14160cb"
            hex"0000000600000006000000060000000600000af400442e66cb8cfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd"
            hex"21a2bfb3c6eae2fad45bdb9c03de1c36b4623858002420430958000000000000000000000060b06c8f130f89587b2f9f14616a67605f6c0f779f"
            hex"25e88690d6765725d138e96c8e1cf26d03db4f8d00845c46162b000000000000000000000000000000000000000000000000000000000000d4310000000000000000000000000000000000000000000000000000000000002ec1000000000000000000000000000000000000000000000004563918244f40000000000000000000000000000000000000000000000000000000000000000000cf"
            hex"5505f95d14925d23138ba726bcae9b3c1d76e82f006478e290260000000000000000000000000000000000000000000000000000000000003eafe8bbfecd380c4167d6a1f763a233ec73e73f534b1970c4e1683f437ec23c1fa5069f7b5e1776a2d4bf57d8efb3ff6de682dcba14407464b37d674a8bd8984c14"
            hex"fdc9796d45cd282f0d859bcc5df82b42da9aa9f300242043095800000000000000000099010b270c4eadbc35e817c9d8e3df614bc833e61e7b6a"
            hex"000000000000000000000000000000000003986000444f7c016a00000000000000000000000000000000000000000000000000001cb7b4975d640b2b8a5b401bfa153d1a5583cb5ff0b4077f188930036b71544c19ebeb1a6f52"
            hex"383f924b597ea0250a38c3cb791df8ba4a8a10b20004edb9e516"
            hex"1af7f588a501ea2b5bb3feefa744892aa2cf00e6006454c045cffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd0000000000000000000000000000000000000000000061db68029f0677dbacb3000000000000000000000000000000000000000000003854f53af084b4066a5f"
            hex"ed09fe459eb9609cae49ae22f409fab1a95907250044741943a00000000000000000000000000000000000000000dabb5bd21d0a36ada4830b9d000000000000000000000000000008860d8fa586633a1473567c2fb9b7afbd67"
            hex"137c53ea8dded8f746ee6e3f831227e4983e409f00442e66cb8c00000000006cdb2594596f2a4babfdcc00b8229250f0d964f6bfc1f9b890a8d90000000000000000000000000000003671efc5a817d388d0054fb4b9c49088fc"
            hex"9424d51a154206a5b27ad97bd5fbd9c0b2a088f20024204309580000000000000000000005bdc0c5852840652b382173338cdbb5e1e0662880ac"
            hex"756e0562323adcda4430d6cb456d9151f605290b006454c045cf00a6905455cd3c04041c9e7a73ff716a417e24ba5bf76b1cd33ae3cbd8ed02e2000000000000000000000000000000000000000000bd2deb0527a32d39c7191c00000000000000000000000000000000000000000000000000000000000e540c"
            hex"0000000000000000000000000000001900000002006454c045cf00000000000000000000000000000000000000000000000000000000000000dd000000000000000000000000000000000000000000000000000000000012a57a0000000600000006000000060000000600000006000000060000000600001637"
            hex"000000000000000000000000000000000001b84000442e66cb8c000000000000000000000000000000000000000044a6e6fbe7bea698000a3b9f00000000000000000000000000000000000000000000017a4c9565c1991cdd93"
            hex"000000000000000000000000000000060003b190002420430958fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe"
            hex"fe33fc20ed69a9895cde1f18c7dcabca39d6a8ad00245ea764670000000000000000000000000000000000000000000000000000000000010d40"
            hex"3c4293f66941eca00f4950c10d4255d5c271baef00242043095800000000000000000000000000000000000000000ceb1ab1e4237b794816ecac"
            hex"0000000000000000000000000000000000005eed00245ea764670000000000000000000000000007c03d7aa68eb51773bedb2db4cfe849457c61"
            hex"756e0562323adcda4430d6cb456d9151f605290b00845c46162b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000013967bfa61c3fd759a4b7d9a27cc210e723000000000000000000000000000000000000000000000000092e55e8ba05efda"
            hex"c88538c2bd90d97bb3f6095d469c76fe40e6a6e40044307556f100000000000000000000000000000000000000000089d910a89b7138ff3d12890000000000000000000000000000000000000000000000002415cfae31f5075e"
            hex"0000000000000000000000000000000000001911006402841e520000000000000000000000000000000000000000000000000000000000001bd50600b8b9e235c0286c80de9e8be71551570e43a53c2a3d98242cd198b372fe4300000000000000000000000000000000000000000000000000000000000000e7"
            hex"d019561193c65e6fdcecbdb33ae8bfd0f5ebb38e006402841e52fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd000000000000000000000000000995d9299b6b14fe96ce773b480b2993c52cfd00000012cceed55c18db36525311d6eac7eff2dd6fe2f06071d7aa2a87774b7e"
            hex"7fa9385be102ac3eac297483dd6233d62b3e14960044741943a000000000000000000000000000000000000004fc100310a8d6e354f703504593ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
            hex"b1a876f2af957c14a29118dc622648c445020ddd006402841e5200000000000000000000000000000000000000000000000000000000005b8d808ec8665ec920fe96c1310d2a3a7ce5e014468d78d979238c957eb811b63c84b60000000000000000000000000000000000000000000000000000000000000384"
            hex"5cafb4c9bddf994b9993f435f42926ffe699659f00442e66cb8c00000000000000000000000000000000000000000000000000000000002f4d600000000000000000000000000000000000000006000000060000000600000124";
        uint256 actions = _replaySequence(replay);
        assertEq(actions, 75);
        handler.finish(17);
        assertEq(handler.ghost_violations(), 0, "original trace per-call liveness");
        console.log("PRESERVED_SEQUENCE_TERMINAL", handler.finishTerminal());
        console.log("PRESERVED_SEQUENCE_LOGICAL_DAY", uint256(game.currentDayView_g542950()));
        assertCompletionOutcome();
    }

    function test_Preserved121ActionsDrainBeforeAdvancingTime() public {
        assertEq(_replaySequence(DegenesisCompletionReplay.calls()), 121);
        assertFalse(handler.deadlineDue(), "saved trace enters completion healthy");
        handler.finish(uint256(keccak256(abi.encode(block.timestamp, handler.ghost_actions()))));
        assertEq(handler.deadlineObservedAt(), 0, "completion cannot manufacture a deadline");
        assertGt(handler.finishDrainCapHits(), 0, "exercise the bounded drain continuation");
        assertFalse(handler.finishTerminal(), "saved healthy trace completes the sale");
        assertEq(handler.ghost_violations(), 0, "each admitted mine call progresses");
        assertCompletionOutcome();
    }

    function _replaySequence(bytes memory replay) private returns (uint256 actions) {
        uint256 cursor;
        while (cursor < replay.length) {
            address sender;
            uint256 size;
            assembly ("memory-safe") {
                sender := shr(96, mload(add(add(replay, 32), cursor)))
                size := shr(240, mload(add(add(replay, 52), cursor)))
            }
            cursor += 22;
            bytes memory input = new bytes(size);
            assembly ("memory-safe") { mcopy(add(input, 32), add(add(replay, 32), cursor), size) }
            cursor += size;
            vm.prank(sender);
            (bool ok,) = address(handler).call(input);
            assertTrue(ok, "preserved handler action must run");
            ++actions;
        }
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
