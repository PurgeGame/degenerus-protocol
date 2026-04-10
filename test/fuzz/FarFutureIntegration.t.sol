// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @title FFKeyComputer -- Exposes internal key computation helpers for test inspection
/// @notice Inherits DegenerusGameStorage solely to access _tqFarFutureKey as public pure.
contract FFKeyComputer is DegenerusGameStorage {
    /// @notice Compute the far-future key for a level.
    function tqFarFutureKey(uint24 lvl) external pure returns (uint24) {
        return _tqFarFutureKey(lvl);
    }
}

/// @title FarFutureIntegrationTest -- TEST-05: Multi-level lifecycle proving zero FF ticket stranding
/// @notice Deploys the full 23-contract protocol via DeployProtocol, drives the game through
///         level transitions past level 7 (where constructor-deposited FF entries exist), and
///         verifies that advanceGame's internal processFutureTicketBatch drains FF queues.
///
///         The constructor pre-queues 16 sDGNRS + 16 vault tickets for levels 1-100.
///         At construction time (level=0), levels 6-100 have targetLevel > 0+5 = true,
///         so they route to FF key. This test proves those entries are processed (drained)
///         when the game reaches those levels.
///
///         Key assertions:
///         1. Constructor pre-queues 2 unique addresses in FF key at levels 6+ (sDGNRS + VAULT)
///            (ticketQueue stores unique addresses, not ticket counts; each address gets 16 tickets
///            tracked separately in ticketsOwedPacked)
///         2. Game advances past level 5 without reverting (proves FF processing works)
///         3. FF queues for processed levels drain to zero (addresses removed after processing)
///
/// @dev To fast-track level transitions, this test seeds the nextPrizePool via vm.store
///      to just below the BOOTSTRAP_PRIZE_POOL target (50 ETH). A small purchase then triggers
///      the level transition without burning gas on prize pool accumulation.
///      Storage layout: prizePoolsPacked at slot 2 = [128:256] future | [0:128] next.
contract FarFutureIntegrationTest is DeployProtocol {
    /// @dev Storage slot of ticketQueue mapping in DegenerusGameStorage (confirmed via forge inspect)
    uint256 private constant TICKET_QUEUE_SLOT = 12;

    /// @dev Storage slot of prizePoolsPacked in DegenerusGameStorage (confirmed via forge inspect)
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;

    FFKeyComputer private ffComputer;
    address private buyer;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        // Deploy key computer for FF key calculation
        ffComputer = new FFKeyComputer();

        // Create and fund buyer
        buyer = makeAddr("integration_buyer");
        vm.deal(buyer, 10_000 ether);

        // Seed the game contract with ETH to back the prize pool we'll inject.
        // This ensures solvency: the game contract balance covers pool obligations.
        vm.deal(address(game), 500 ether);
    }

    /// @notice Main integration test: drive game through multiple levels, verify zero FF stranding
    function testMultiLevelAdvancementWithFFTickets() public {
        // --- Phase 1: Verify initial state ---
        assertEq(game.level(), 0, "Initial level should be 0");

        // Verify constructor pre-queued FF entries at levels 6, 7, 8.
        // ticketQueue[key] is an address[] of unique buyers. The constructor queues tickets
        // for 2 addresses (sDGNRS and VAULT) at each level, so the array length is 2.
        // Each address has 16 tickets tracked in ticketsOwedPacked (not in the array length).
        uint256 ffLen6 = _ffQueueLength(6);
        assertEq(ffLen6, 2, "Constructor should pre-queue 2 FF addresses at level 6 (sDGNRS + VAULT)");

        uint256 ffLen7 = _ffQueueLength(7);
        assertEq(ffLen7, 2, "Constructor should pre-queue 2 FF addresses at level 7 (sDGNRS + VAULT)");

        uint256 ffLen8 = _ffQueueLength(8);
        assertEq(ffLen8, 2, "Constructor should pre-queue 2 FF addresses at level 8 (sDGNRS + VAULT)");

        // Verify level 5 is NOT in FF key (5 <= 0+5, routes to write key)
        uint256 ffLen5 = _ffQueueLength(5);
        assertEq(ffLen5, 0, "Level 5 should NOT have FF entries (5 <= 0+5)");

        // --- Phase 2: Drive game through levels ---
        // Each level requires:
        //   1. nextPrizePool >= levelPrizePool[level] (prize pool target met)
        //   2. advanceGame daily cycles: ticket processing -> VRF -> daily jackpot -> if target met,
        //      transition to jackpot phase -> 5 jackpot days -> phase transition -> level++
        //
        // To fast-track: seed nextPrizePool to 49.9 ETH (just below 50 ETH target), buy a small
        // quantity to push it over, then drive the advance cycle. This avoids burning gas on
        // hundreds of purchases just to fill the pool.

        uint256 simTime = block.timestamp; // start at 86400 (deploy time)

        for (uint256 day = 0; day < 300; day++) {
            if (game.level() >= 6) break;
            if (game.gameOver()) break;

            // Advance to next day
            simTime += 1 days + 1;
            vm.warp(simTime);

            // Seed next prize pool high enough to trigger transition.
            // prizePoolsPacked = [future:128] [next:128]
            // Set next to 49.9 ether (just below 50 ether BOOTSTRAP_PRIZE_POOL target)
            // Future stays at 0.
            // This only takes effect if the pool hasn't already been filled.
            _seedNextPrizePool(49.9 ether);

            // Buy tickets to push over the target and create actual ticket entries
            _buyTickets(buyer, 4000);

            // Drive advanceGame + VRF fulfillment until nothing more to do today
            for (uint256 j = 0; j < 50; j++) {
                _fulfillVrfIfPending();

                (bool ok, ) = address(game).call(
                    abi.encodeWithSignature("advanceGame()")
                );
                if (!ok) break; // NotTimeYet = done for this day
            }
        }

        // --- Phase 3: Assert game advanced past FF-containing levels ---
        // At level 4, _prepareFutureTickets(4) processes levels 6-9 (draining their FF entries).
        uint256 finalLevel = game.level();
        emit log_named_uint("Final level reached", finalLevel);
        assertGe(finalLevel, 5, "Game should advance past level 4 where FF entries at 6-9 are processed");

        // --- Phase 4: Verify FF queues for processed levels are drained ---
        // _prepareFutureTickets at level L processes levels L+2..L+5.
        // By level 5, levels 6-10 have been in processing range.
        uint256 ffLen6After = _ffQueueLength(6);
        assertEq(ffLen6After, 0, "FF queue for level 6 should be drained to zero after processing");

        uint256 ffLen7After = _ffQueueLength(7);
        assertEq(ffLen7After, 0, "FF queue for level 7 should be drained to zero after processing");

        uint256 ffLen8After = _ffQueueLength(8);
        assertEq(ffLen8After, 0, "FF queue for level 8 should be drained to zero after processing");
    }

    // ==================== Internal Helpers ====================

    /// @notice Read the length of the FF queue for a given level from game contract storage
    /// @dev ticketQueue is a mapping(uint24 => address[]) at slot 15.
    ///      For a dynamic array in a mapping, the length is stored at:
    ///        keccak256(abi.encode(uint256(key), uint256(baseSlot)))
    function _ffQueueLength(uint24 lvl) internal view returns (uint256) {
        uint24 ffKey = ffComputer.tqFarFutureKey(lvl);
        bytes32 slot = keccak256(abi.encode(uint256(ffKey), uint256(TICKET_QUEUE_SLOT)));
        return uint256(vm.load(address(game), slot));
    }

    /// @notice Seed the next prize pool to accelerate level transitions
    /// @dev Sets prizePoolsPacked slot 3: lower 128 bits = nextPrizePool.
    ///      Preserves the upper 128 bits (futurePrizePool).
    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 currentPacked = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint128 currentNext = uint128(currentPacked);
        // Only seed if current next pool is below target
        if (uint256(currentNext) >= targetNext) return;
        uint128 currentFuture = uint128(currentPacked >> 128);
        uint256 newPacked = (uint256(currentFuture) << 128) | targetNext;
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
    }

    /// @notice Buy tickets for the buyer at the current price
    function _buyTickets(address who, uint256 qty) internal {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();

        // Cannot purchase while RNG is locked or game over
        if (rngLocked_) return;
        if (game.gameOver()) return;

        // Cost calculation matches production: priceWei is per 400 tickets
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;

        // Ensure buyer has enough ETH (top up if needed)
        if (who.balance < cost) {
            vm.deal(who, cost + 10 ether);
        }

        vm.prank(who);
        try game.purchase{value: cost}(
            who,
            qty,
            0,
            bytes32(0),
            MintPaymentKind.DirectEth
        ) {} catch {}
    }

    /// @notice Check for pending VRF request and fulfill it with a deterministic random word
    function _fulfillVrfIfPending() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;

        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;

        // Use deterministic random word derived from current state
        uint256 randomWord = uint256(keccak256(abi.encode(
            block.timestamp,
            game.level(),
            reqId
        )));

        try mockVRF.fulfillRandomWords(reqId, randomWord) {} catch {}
    }
}
