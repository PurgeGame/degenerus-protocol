// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {VRFHandler} from "../helpers/VRFHandler.sol";
import {TicketTrackingHandler} from "../handlers/TicketTrackingHandler.sol";

/// @title TicketQueueInvariant -- Proves ticket queue ordering holds (FUZZ-05)
/// @notice The _queueEntries function only pushes a player to ticketQueue[_ticketQueueStorageKey(level)]
///         when their entriesOwedPacked is zero (no prior entry). This invariant
///         verifies that the tracking is consistent and no player has negative
///         or corrupted ticket owed state.
contract TicketQueueInvariant is DeployProtocol {
    TicketTrackingHandler public ticketHandler;
    VRFHandler public vrfHandler;

    function setUp() public virtual {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        ticketHandler = new TicketTrackingHandler(game, 10);
        vrfHandler = new VRFHandler(mockVRF, game);

        targetContract(address(ticketHandler));
        targetContract(address(vrfHandler));
    }

    /// @notice No consistency violations in ticket tracking
    /// @dev verifyConsistency asserts (and so reverts on a violation) the three cohort queues against the raw
    ///      position records and every actor's address-facing view, at every level up to level + 5.
    function invariant_noConsistencyViolations() public view {
        for (uint256 lvl; lvl <= uint256(game.level()) + 5; ++lvl) ticketHandler.verifyConsistency(lvl);
    }

    /// @notice Ticket owed view should return 0 for addresses that never purchased
    /// @dev Pick an address that was never used as an actor. Their ticketsOwed
    ///      at any level should be 0.
    function invariant_nonParticipantHasNoTickets() public view {
        // Address 0xDEAD was never registered as an actor
        address nonParticipant = address(0xDEAD);
        uint24 currentLevel = game.level();

        // Check current level and next level
        assertEq(
            game.entriesOwedView(currentLevel, nonParticipant),
            0,
            "TicketQueue: non-participant has tickets at current level"
        );
        assertEq(
            game.entriesOwedView(currentLevel + 1, nonParticipant),
            0,
            "TicketQueue: non-participant has tickets at next level"
        );
    }

    /// @dev Non-vacuity. Per run the queue
    ///      must actually be drained and fed words: measured minima over 771 default-profile runs were 3
    ///      successful mineFlips and 1 VRF fulfilment. Purchases can legitimately all fail in one run (an early
    ///      daily-RNG lock; 127 of 771 runs had none), so purchases and queued entries are accumulated over the
    ///      process (unique TQ_ prefix) and must be non-zero once MIN_RUNS runs have completed.
    uint256 private constant MIN_RUNS = 16;

    function _acc(string memory k, uint256 v) internal virtual returns (uint256 total) {
        total = vm.envOr(k, uint256(0)) + v;
        vm.setEnv(k, vm.toString(total));
    }

    function afterInvariant() public {
        assertGe(ticketHandler.ghost_advances(), 1, "vacuous: mineFlip never succeeded in this run");
        assertGe(vrfHandler.ghost_vrfFulfillments(), 1, "vacuous: no VRF word was fulfilled in this run");
        uint256 runs = _acc("TQ_RUNS", 1);
        uint256 purchases = _acc("TQ_purchases", ticketHandler.ghost_purchases());
        uint256 entries = _acc("TQ_entries", ticketHandler.ghost_totalEntries());
        if (runs < MIN_RUNS) return;
        assertGt(purchases, 0, "vacuous: no ticket purchase ever succeeded");
        assertGt(entries, 0, "vacuous: no purchase ever left queued entries");
    }

}
