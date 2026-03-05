// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";

/// @title MultiLevelHandler -- Handler for deep multi-level game progression
/// @notice Drives the game through purchase -> VRF -> advance -> next level cycles.
///         Previous fuzzing was limited to levels 0-2. This handler targets level 10+
///         with price escalation and pool growth tracking.
/// @dev Actors are funded with large ETH balances to sustain purchases at escalating prices.
///      Ghost variables track pool balances at each level transition for solvency verification.
contract MultiLevelHandler is Test {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;

    // --- Ghost variables ---
    uint256 public ghost_maxLevel;
    uint256 public ghost_totalDeposited;
    uint256 public ghost_levelTransitions;
    uint256 public ghost_vrfFulfillments;

    // Pool snapshots at level transitions
    uint256 public ghost_lastCurrentPool;
    uint256 public ghost_lastNextPool;
    uint256 public ghost_lastFuturePool;
    uint256 public ghost_lastClaimablePool;

    // Price tracking
    uint256 public ghost_minPrice;
    uint256 public ghost_maxPrice;
    bool public ghost_priceInitialized;

    // --- Call counters ---
    uint256 public calls_purchase;
    uint256 public calls_advanceGame;
    uint256 public calls_fulfillVrf;
    uint256 public calls_heavyPurchase;

    // --- Actor management ---
    address[] public actors;
    address internal currentActor;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    constructor(DegenerusGame game_, MockVRFCoordinator vrf_, uint256 numActors) {
        game = game_;
        vrf = vrf_;
        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0xAA000 + i));
            actors.push(actor);
            // Large balance: 10000 ETH each for deep level progression
            vm.deal(actor, 10_000 ether);
        }
    }

    /// @notice Heavy purchase to rapidly fill prize pool and trigger level transitions
    /// @param actorSeed Seed for actor selection
    /// @param qty Raw quantity, bounded to [1000, 4000]
    function heavyPurchase(
        uint256 actorSeed,
        uint256 qty
    ) external useActor(actorSeed) {
        calls_heavyPurchase++;

        if (game.gameOver()) return;

        qty = bound(qty, 1000, 4000);

        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0 || cost > currentActor.balance) return;

        uint256 levelBefore = game.level();

        vm.prank(currentActor);
        try game.purchase{value: cost}(
            currentActor,
            qty,
            0,
            bytes32(0),
            MintPaymentKind.DirectEth
        ) {
            ghost_totalDeposited += cost;

            // Track price
            if (!ghost_priceInitialized) {
                ghost_minPrice = priceWei;
                ghost_maxPrice = priceWei;
                ghost_priceInitialized = true;
            } else {
                if (priceWei < ghost_minPrice) ghost_minPrice = priceWei;
                if (priceWei > ghost_maxPrice) ghost_maxPrice = priceWei;
            }
        } catch {}

        _checkLevelTransition(levelBefore);
    }

    /// @notice Standard purchase with smaller quantities
    /// @param actorSeed Seed for actor selection
    /// @param qty Raw quantity, bounded to [100, 1000]
    function purchase(
        uint256 actorSeed,
        uint256 qty
    ) external useActor(actorSeed) {
        calls_purchase++;

        if (game.gameOver()) return;

        qty = bound(qty, 100, 1000);

        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0 || cost > currentActor.balance) return;

        uint256 levelBefore = game.level();

        vm.prank(currentActor);
        try game.purchase{value: cost}(
            currentActor,
            qty,
            0,
            bytes32(0),
            MintPaymentKind.DirectEth
        ) {
            ghost_totalDeposited += cost;
        } catch {}

        _checkLevelTransition(levelBefore);
    }

    /// @notice Advance game (crucial for level transitions)
    /// @param actorSeed Seed for actor selection
    function advanceGame(uint256 actorSeed) external useActor(actorSeed) {
        calls_advanceGame++;

        if (game.gameOver()) return;

        uint256 levelBefore = game.level();

        vm.prank(currentActor);
        try game.advanceGame() {} catch {}

        _checkLevelTransition(levelBefore);
    }

    /// @notice Fulfill VRF to unblock level transitions
    /// @param randomWord Random word for VRF fulfillment
    function fulfillVrf(uint256 randomWord) external {
        calls_fulfillVrf++;

        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return;

        (, , bool fulfilled) = vrf.pendingRequests(reqId);
        if (fulfilled) return;

        uint256 levelBefore = game.level();

        try vrf.fulfillRandomWords(reqId, randomWord) {
            ghost_vrfFulfillments++;
        } catch {}

        _checkLevelTransition(levelBefore);
    }

    /// @notice Warp past a game day to enable daily jackpots
    function warpDay() external {
        vm.warp(block.timestamp + 1 days + 1);
    }

    /// @notice Warp past VRF timeout
    function warpPastVrfTimeout() external {
        vm.warp(block.timestamp + 18 hours + 1);
    }

    /// @notice Small time warp
    function warpTime(uint256 delta) external {
        delta = bound(delta, 1 minutes, 12 hours);
        vm.warp(block.timestamp + delta);
    }

    // --- Internal helpers ---

    function _checkLevelTransition(uint256 levelBefore) private {
        uint256 levelAfter = game.level();
        if (levelAfter > levelBefore) {
            ghost_levelTransitions++;
            if (levelAfter > ghost_maxLevel) {
                ghost_maxLevel = levelAfter;
            }
            // Snapshot pool state at transition
            ghost_lastCurrentPool = game.currentPrizePoolView();
            ghost_lastNextPool = game.nextPrizePoolView();
            ghost_lastFuturePool = game.futurePrizePoolTotalView();
            ghost_lastClaimablePool = game.claimablePoolView();
        }
    }
}
