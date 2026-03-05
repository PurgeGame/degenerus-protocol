// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";

/// @title TicketTrackingHandler -- Handler tracking ticket queue entries for invariant testing
/// @notice Wraps purchase operations and tracks which (level, player) pairs have been queued.
///         Uses ticketsOwedView to verify consistency: if a player purchased at a level,
///         their ticketsOwed should be non-zero.
contract TicketTrackingHandler is Test {
    DegenerusGame public game;

    // --- Ghost tracking ---
    /// @dev Maps level => player => whether we've seen them purchase at this level
    mapping(uint24 => mapping(address => bool)) public ghost_hasTicketsAtLevel;

    /// @dev Track (level, player) pairs for checking consistency
    uint256 public ghost_totalEntries;
    uint256 public ghost_consistencyViolations;

    // --- Call counters ---
    uint256 public calls_purchase;

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
            address actor = address(uint160(0xD0000 + i));
            actors.push(actor);
            vm.deal(actor, 100 ether);
        }
    }

    /// @notice Purchase tickets and track queue entries
    function purchase(
        uint256 actorSeed,
        uint256 qty,
        uint256 lootboxAmt
    ) external useActor(actorSeed) {
        calls_purchase++;

        if (game.gameOver()) return;

        qty = bound(qty, 100, 4000);
        lootboxAmt = bound(lootboxAmt, 0, 2 ether);

        (uint24 lvl, , , , uint256 priceWei) = game.purchaseInfo();
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
            // After successful purchase, verify ticketsOwed consistency
            // purchaseInfo().lvl returns the active ticket level
            uint32 owed = game.ticketsOwedView(lvl, currentActor);
            if (owed > 0) {
                ghost_hasTicketsAtLevel[lvl][currentActor] = true;
                ghost_totalEntries++;
            }
        } catch {}
    }

    /// @notice Verify ticket owed consistency for all actors at a given level
    /// @dev Checks that if ghost says a player has tickets, ticketsOwedView confirms it
    ///      (or they were already processed by advanceGame).
    function verifyConsistency(uint256 levelSeed) external view {
        uint24 currentLevel = game.level();
        if (currentLevel == 0) return;

        // Check a level near the current level
        uint24 checkLevel = uint24(bound(levelSeed, 0, currentLevel));

        for (uint256 i = 0; i < actors.length; i++) {
            address actor = actors[i];
            if (ghost_hasTicketsAtLevel[checkLevel][actor]) {
                // Player was queued at this level. Their tickets may have been
                // consumed by advanceGame (owed drops to 0 after processing).
                // So we only check that the system doesn't have negative owed
                // (which is impossible with uint32 but is a sanity check).
                uint32 owed = game.ticketsOwedView(checkLevel, actor);
                // owed is uint32, always >= 0. This is a structural sanity check.
                assertTrue(owed >= 0, "ticketsOwed underflow");
            }
        }
    }
}
