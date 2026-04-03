// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {VRFHandler} from "./helpers/VRFHandler.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title VRFLifecycle -- Proves VRF fulfillment works and game advances past level 0
/// @notice Final validation that Phase 14 infrastructure is ready for invariant testing.
contract VRFLifecycle is DeployProtocol {
    VRFHandler public vrfHandler;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vrfHandler = new VRFHandler(mockVRF, game);
    }

    /// @notice Verify VRF fulfillment mechanism works with the mock
    function test_vrfFulfillmentWorks() public {
        // Initially no VRF requests
        assertEq(mockVRF.lastRequestId(), 0, "Should have no requests initially");

        // Trigger a VRF request by calling advanceGame
        // At deploy time (timestamp=86400), dayIndex=1 > dailyIdx=0, so advanceGame proceeds
        game.advanceGame();

        // VRF request should have been sent
        assertTrue(game.rngLocked(), "rngLocked should be true after advanceGame");
        uint256 reqId = mockVRF.lastRequestId();
        assertTrue(reqId > 0, "Should have a VRF request");

        // Fulfill the VRF request
        mockVRF.fulfillRandomWords(reqId, 12345);

        // RNG word is stored but game still locked until advanceGame processes it
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        assertTrue(fulfilled, "VRF request should be fulfilled");
    }

    /// @notice Full VRF daily cycle: purchase -> warp day -> advanceGame -> VRF fulfill -> unlock
    function test_fullVrfDailyCycle() public {
        assertEq(game.level(), 0, "Game should start at level 0");

        // Buy some tickets at level 0
        address buyer = makeAddr("buyer");
        vm.deal(buyer, 100 ether);
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(buyer);
            game.purchase{value: 0.01 ether}(
                buyer,
                400,
                0,
                bytes32(0),
                MintPaymentKind.DirectEth
            );
        }

        // Warp to next day
        vm.warp(block.timestamp + 1 days);

        // Trigger VRF request
        game.advanceGame();
        assertTrue(game.rngLocked(), "rngLocked after advanceGame");

        // Fulfill VRF
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, 12345678901234567890);

        // Drive advances until RNG unlocks
        for (uint256 i = 0; i < 30; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }

        assertFalse(game.rngLocked(), "rngLocked should be false after full cycle");
        // Level stays at 0 in purchase phase (prize target not met) -- this is correct
        assertEq(game.level(), 0, "Level 0 stays until prize target met");
    }

    /// @notice Game advances past level 0 when enough ETH accumulates in the prize pool
    /// @dev This test purchases enough ETH via lootboxes to hit the 50 ETH prize target,
    ///      then drives through the jackpot phase transition to prove level advancement works.
    function test_vrfLifecycle_levelAdvancement() public {
        assertEq(game.level(), 0, "Game should start at level 0");

        // Fund a buyer with enough ETH to hit the 50 ETH nextPrizePool target.
        // Presale lootbox split: 40% to nextPrizePool. Ticket cost also contributes
        // 90% of 0.01 ETH to nextPrizePool. Need ~200 purchases of 1 ETH lootbox
        // to ensure we exceed the 50 ETH bootstrap threshold accounting for all splits.
        address buyer = makeAddr("buyer");
        vm.deal(buyer, 500 ether);

        for (uint256 i = 0; i < 200; i++) {
            vm.prank(buyer);
            game.purchase{value: 1.01 ether}(
                buyer,
                400,       // 1 full ticket
                1 ether,   // lootbox amount
                bytes32(0),
                MintPaymentKind.DirectEth
            );
        }

        // Drive daily VRF cycles until level changes or we've done enough days.
        // The game needs to:
        //   1. Accumulate enough in nextPrizePool (>= BOOTSTRAP_PRIZE_POOL = 50 ETH)
        //   2. Process via daily advance (triggers lastPurchaseDay=true)
        //   3. Process jackpot phase (multiple days of jackpot draws)
        //   4. Complete phase transition -> level increments
        uint24 initialLevel = game.level();
        uint256 ts = block.timestamp;
        uint256 lastFulfilledId;
        for (uint256 day = 0; day < 30; day++) {
            ts += 1 days;
            vm.warp(ts);

            // Try advanceGame -- may revert if not ready
            try game.advanceGame() {} catch { continue; }

            // If a new VRF request was fired, fulfill it
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId > lastFulfilledId && reqId > 0) {
                try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode(day)))) {
                    lastFulfilledId = reqId;
                } catch {}
            }

            // Process until unlocked (may take multiple calls as tickets are batched)
            for (uint256 j = 0; j < 50; j++) {
                if (!game.rngLocked()) break;
                try game.advanceGame() {} catch { break; }
            }

            // Check if level changed
            if (game.level() > initialLevel) break;
        }

        assertTrue(game.level() > initialLevel, "Game should advance past level 0");
    }

    /// @notice VRFHandler ghost tracking works correctly
    function test_vrfHandlerTracking() public {
        assertEq(vrfHandler.ghost_vrfFulfillments(), 0, "Should start at 0 fulfillments");

        // No request yet -- fulfillVrf should be a no-op
        vrfHandler.fulfillVrf(42);
        assertEq(vrfHandler.ghost_vrfFulfillments(), 0, "No-op when no requests");

        // Trigger a VRF request
        game.advanceGame();
        assertTrue(game.rngLocked(), "rngLocked after advanceGame");

        // Fulfill via handler
        vrfHandler.fulfillVrf(99999);
        assertEq(vrfHandler.ghost_vrfFulfillments(), 1, "Should have 1 fulfillment");

        // Fulfilling again should be a no-op (already fulfilled)
        vrfHandler.fulfillVrf(11111);
        assertEq(vrfHandler.ghost_vrfFulfillments(), 1, "Should still have 1 fulfillment");
    }
}
