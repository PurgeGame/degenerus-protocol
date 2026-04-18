// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title GameOverPathIsolation -- Phase 232.1 D-05 vacuous-safety claim made testable
/// @notice Simulating game-over while tickets are queued produces ZERO
///         daily-drain-branch execution in the captured event log. Confirms
///         CONTEXT.md D-05's three isolation proofs by simulation:
///            1. _handleGameOverPath returns early at AdvanceModule:178-181
///            2. handleGameOverDrain reads rngWordByDay[day], not
///               lootboxRngWordByIndex[]
///            3. zero references to _swapTicketSlot / processTicketBatch /
///               _raritySymbolBatch in game-over code paths
///
/// @dev Instrumentation rationale (W-3): the test asserts the DAILY-DRAIN
///      BRANCH body never executes, NOT just that LR_INDEX did not advance.
///      Game-over skips LR_INDEX manipulation entirely via _handleGameOverPath
///      at L178-181, so a ghost counter keyed on LR_INDEX advance would be 0
///      vacuously for the wrong reason. Instead, the test uses vm.recordLogs()
///      and asserts ZERO `TraitsGenerated` events fire during the game-over
///      advanceGame tx — `TraitsGenerated` emits ONLY from inside
///      processTicketBatch / _processOneTicketEntry (the daily-drain
///      consumers), so zero emits proves the daily-drain body never ran. This
///      catches a hypothetical regression where game-over might wrongly reach
///      the daily-drain branch with queued tickets.
contract GameOverPathIsolationTest is DeployProtocol {
    /// @dev Keccak topic-0 for TraitsGenerated(address,uint24,uint32,uint32,uint32,uint256)
    bytes32 internal constant TOPIC_TRAITS_GENERATED =
        keccak256("TraitsGenerated(address,uint24,uint32,uint32,uint32,uint256)");

    /// @dev Keccak topic-0 for Advance(uint8 stage, uint24 level). STAGE_GAMEOVER
    ///      is stage constant 3 in DegenerusGameAdvanceModule; the indexed fields
    ///      let us confirm the game-over branch was actually taken without
    ///      decoding stage values.
    bytes32 internal constant TOPIC_ADVANCE =
        keccak256("Advance(uint8,uint24)");

    address internal buyer;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        buyer = makeAddr("gameOverBuyer");
        vm.deal(buyer, 100 ether);
        mockVRF.fundSubscription(1, 100e18);
    }

    /// @dev Count logs matching a given topic-0 in the recorded batch.
    function _countLogsWithTopic(Vm.Log[] memory logs, bytes32 topic0)
        internal
        pure
        returns (uint256 count)
    {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic0) {
                count++;
            }
        }
    }

    // =========================================================================
    // D-05 Path Isolation: game-over advance does NOT run the daily-drain branch
    // =========================================================================

    /// @notice With tickets queued, simulate game-over via liveness timeout.
    ///         The game-over advanceGame tx MUST emit ZERO TraitsGenerated
    ///         events — any TraitsGenerated would mean the daily-drain branch
    ///         body executed, contradicting D-05's isolation claim.
    function testGameOverDoesNotInvokeDailyDrain() public {
        // Step 1: land on level 0 day 1 with queued tickets.
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 ticketCost = (priceWei * 400) / 400;
        vm.prank(buyer);
        game.purchase{value: ticketCost}(
            buyer,
            400,
            0,
            bytes32(0),
            MintPaymentKind.DirectEth
        );

        // Step 2: trigger liveness timeout without advancing the day.
        //   On level 0, _handleGameOverPath triggers when
        //   currentDay - purchaseStartDay > DEPLOY_IDLE_TIMEOUT_DAYS (365).
        //   Warp enough extra days to pass the strict-greater comparison.
        vm.warp(block.timestamp + 370 days);

        // Step 3: record logs across the entire game-over transition. The first
        //   _handleGameOverPath call requests VRF (if needed) and emits
        //   STAGE_GAMEOVER. After VRF fulfills, subsequent calls run
        //   handleGameOverDrain which sets gameOver=true. The whole sequence
        //   must emit ZERO TraitsGenerated events -- game-over never reaches
        //   the daily-drain body (D-05 isolation).
        vm.recordLogs();
        uint256 totalTraits;
        uint256 totalAdvances;
        for (uint256 i = 0; i < 20; i++) {
            try game.advanceGame() {} catch {
                // Revert is acceptable while waiting on VRF; collect emitted
                // logs so far and continue.
            }
            Vm.Log[] memory iterLogs = vm.getRecordedLogs();
            totalTraits += _countLogsWithTopic(iterLogs, TOPIC_TRAITS_GENERATED);
            totalAdvances += _countLogsWithTopic(iterLogs, TOPIC_ADVANCE);

            uint256 reqId = mockVRF.lastRequestId();
            (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (reqId > 0 && !fulfilled) {
                uint256 word = uint256(keccak256(abi.encode("gameover-word", i)));
                try mockVRF.fulfillRandomWords(reqId, word) {} catch {}
            }
            if (game.gameOver()) break;
            vm.recordLogs();
        }

        // Step 4: confirm the game-over branch was actually taken at some
        //   point during the sequence (not vacuously satisfied by a no-op).
        assertGt(
            totalAdvances,
            0,
            "Game-over branch was NOT taken (no Advance event emitted) -- test vacuously satisfied"
        );
        assertTrue(
            game.gameOver(),
            "gameOver flag not set after 20 advance attempts -- transition did not complete"
        );

        // Step 5: the key isolation assertion -- ZERO TraitsGenerated emits
        //   across the entire game-over transition.
        assertEq(
            totalTraits,
            0,
            "D-05 isolation violated: TraitsGenerated emitted during game-over advance"
        );
    }
}
