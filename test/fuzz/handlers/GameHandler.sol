// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";

/// @title GameHandler -- Handler for core game operations in invariant tests
/// @notice Wraps purchase/advanceGame/claimWinnings with bounded inputs,
///         multi-actor support, and ghost variable ETH tracking.
contract GameHandler is Test {
    DegenerusGame public game;

    // --- Ghost variables ---
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalClaimed;
    uint256 public ghost_ticketsPurchased;
    uint256 public ghost_maxLevelReached;
    uint256 public ghost_successfulPurchases;
    uint256 public ghost_successfulAdvances;

    // --- Call counters ---
    uint256 public calls_purchase;
    uint256 public calls_advanceGame;
    uint256 public calls_claimWinnings;

    // --- Actor management ---
    address[] public actors;
    address internal currentActor;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    constructor(DegenerusGame game_, uint256 numActors) {
        game = game_;
        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0xA0000 + i));
            actors.push(actor);
            vm.deal(actor, 100 ether);
        }
    }

    /// @notice Purchase tickets with bounded inputs
    /// @param actorSeed Seed for actor selection
    /// @param qty Raw ticket quantity, bounded to [100, 4000]
    /// @param lootboxAmt Raw lootbox amount, bounded to [0, 2 ether]
    function purchase(
        uint256 actorSeed,
        uint256 qty,
        uint256 lootboxAmt
    ) external useActor(actorSeed) {
        calls_purchase++;

        if (game.gameOver()) return;

        // Bound inputs
        qty = bound(qty, 100, 4000);
        lootboxAmt = bound(lootboxAmt, 0, 2 ether);

        // Get current price
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 ticketCost = (priceWei * qty) / 400;
        uint256 totalCost = ticketCost + lootboxAmt;

        if (totalCost == 0 || totalCost > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchase{value: totalCost}(
            currentActor,
            qty,
            lootboxAmt,
            bytes32(0),
            MintPaymentKind.DirectEth
        ) {
            ghost_totalDeposited += totalCost;
            ghost_ticketsPurchased += qty;
            ghost_successfulPurchases++;
        } catch {}
    }

    /// @notice Call advanceGame to progress the state machine
    /// @param actorSeed Seed for actor selection
    function advanceGame(uint256 actorSeed) external useActor(actorSeed) {
        calls_advanceGame++;

        if (game.gameOver()) return;

        vm.prank(currentActor);
        try game.advanceGame() {
            ghost_successfulAdvances++;
            uint256 currentLevel = game.level();
            if (currentLevel > ghost_maxLevelReached) {
                ghost_maxLevelReached = currentLevel;
            }
        } catch {}
    }

    /// @notice Claim winnings for an actor
    /// @param actorSeed Seed for actor selection
    function claimWinnings(uint256 actorSeed) external useActor(actorSeed) {
        calls_claimWinnings++;

        uint256 balBefore = currentActor.balance;

        vm.prank(currentActor);
        try game.claimWinnings(currentActor) {
            uint256 balAfter = currentActor.balance;
            if (balAfter > balBefore) {
                ghost_totalClaimed += balAfter - balBefore;
            }
        } catch {}
    }
}
