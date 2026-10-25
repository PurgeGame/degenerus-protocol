// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {SolvencyObligations} from "../helpers/SolvencyObligations.sol";

/// @title CompositionHandler -- Handler for cross-module composition invariant tests
/// @notice Exercises cross-module state transitions and tracks ghost variables
///         for composition safety invariants (pool solvency, level monotonicity, game-over latch).
/// @dev Uses FOUNDRY_PROFILE=deep for 1K invariant runs.
contract CompositionHandler is Test {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;

    // --- Ghost variables for composition invariants ---
    uint256 public ghost_poolSolvencyViolation;
    uint256 public ghost_levelDecreased;
    bool public ghost_gameOverSeen;
    uint256 public ghost_gameOverReversed;
    uint256 public ghost_lastSeenLevel;

    // --- Progress ghosts (successful calls only; read by the suite's afterInvariant) ---
    uint256 public ghost_purchases;
    uint256 public ghost_whalePurchases;
    uint256 public ghost_mineFlips;
    uint256 public ghost_vrfFulfillments;
    uint256 public ghost_maxLevel;

    // --- Call counters ---
    uint256 public calls_purchaseThenAdvance;
    uint256 public calls_whaleThenPurchase;
    uint256 public calls_advanceFullCycle;
    uint256 public calls_purchaseOnly;
    uint256 public calls_warpDay;

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
            address actor = address(uint160(0xC0000 + i));
            actors.push(actor);
            vm.deal(actor, 100 ether);
        }
    }

    // =========================================================================
    // Action: Purchase then Advance (MINT then ADV sequence)
    // =========================================================================

    /// @notice Purchase tickets then call mineFlip -- tests MINT->ADV composition
    function action_purchaseThenAdvance(
        uint256 actorSeed,
        uint256 qty
    ) external useActor(actorSeed) {
        calls_purchaseThenAdvance++;

        if (game.gameOver()) return;

        qty = bound(qty, 100, 2000);

        (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
        uint256 ticketCost = (priceWei * qty) / 400;
        if (ticketCost == 0 || ticketCost > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchase{value: ticketCost}(
            0, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false
        ) {
            ghost_purchases++;
        } catch {}

        // Now advance
        vm.prank(currentActor);
        try game.mineFlip(0) {
            ghost_mineFlips++;
        } catch {}

        _checkCompositionInvariants();
    }

    // =========================================================================
    // Action: Whale Pass then Purchase (WHALE then MINT for same player)
    // =========================================================================

    /// @notice Whale pass then purchase -- tests mintPacked_ shared writes
    function action_whaleThenPurchase(
        uint256 actorSeed,
        uint256 qty
    ) external useActor(actorSeed) {
        calls_whaleThenPurchase++;

        if (game.gameOver()) return;

        // A whale pass needs an unlocked game: answer the daily request and drain the day first.
        _settleDay();

        // Try whale pass first
        uint256 whaleCost = 2.4 ether;
        if (whaleCost <= currentActor.balance) {
            vm.prank(currentActor);
            try game.purchaseWhalePass{value: whaleCost}(0, 1, bytes32(0)) {
                ghost_whalePurchases++;
            } catch {}
        }

        // Then purchase tickets
        qty = bound(qty, 100, 1000);
        (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
        uint256 ticketCost = (priceWei * qty) / 400;
        if (ticketCost > 0 && ticketCost <= currentActor.balance) {
            vm.prank(currentActor);
            try game.purchase{value: ticketCost}(
                0, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false
            ) {
                ghost_purchases++;
            } catch {}
        }

        _checkCompositionInvariants();
    }

    /// @dev Fulfil the pending VRF request and mine until the daily lock clears (bounded).
    function _settleDay() private {
        for (uint256 i; i < 8 && game.rngLocked(); ++i) {
            uint256 reqId = vrf.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = vrf.pendingRequests(reqId);
                if (!fulfilled) {
                    try vrf.fulfillRandomWords(reqId, uint256(keccak256(abi.encode(block.timestamp, reqId)))) {
                        ghost_vrfFulfillments++;
                    } catch {}
                }
            }
            vm.prank(currentActor);
            try game.mineFlip(0) {
                ghost_mineFlips++;
            } catch {}
        }
    }

    // =========================================================================
    // Action: Advance Full Cycle (ADV -> JACK -> MINT -> END -> OVER chain)
    // =========================================================================

    /// @notice Call mineFlip multiple times to drive through orchestration sequence
    function action_advanceFullCycle(
        uint256 actorSeed
    ) external useActor(actorSeed) {
        calls_advanceFullCycle++;

        if (game.gameOver()) return;

        // First ensure actor has purchased today (daily gate)
        (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
        uint256 ticketCost = (priceWei * 100) / 400;
        if (ticketCost > 0 && ticketCost <= currentActor.balance) {
            vm.prank(currentActor);
            try game.purchase{value: ticketCost}(
                0, 100, 0, bytes32(0), MintPaymentKind.DirectEth, false
            ) {
                ghost_purchases++;
            } catch {}
        }

        // Try to advance 3 times (may trigger VRF, jackpot, etc.)
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(currentActor);
            try game.mineFlip(0) {
                ghost_mineFlips++;
            } catch {}
        }

        // Try to fulfill VRF if pending
        uint256 reqId = vrf.lastRequestId();
        if (reqId != 0) {
            (, , bool fulfilled) = vrf.pendingRequests(reqId);
            if (!fulfilled) {
                try vrf.fulfillRandomWords(reqId, uint256(keccak256(abi.encode(block.timestamp, actorSeed)))) {
                    ghost_vrfFulfillments++;
                } catch {}
            }
        }

        // Advance again after VRF
        vm.prank(currentActor);
        try game.mineFlip(0) {
            ghost_mineFlips++;
        } catch {}

        _checkCompositionInvariants();
    }

    // =========================================================================
    // Action: Warp one game day (lets the daily cycle, jackpots and level transitions run)
    // =========================================================================

    function action_warpDay(uint256 extra) external {
        calls_warpDay++;
        vm.warp(block.timestamp + 1 days + bound(extra, 0, 6 hours));
    }

    // =========================================================================
    // Action: Simple purchase (baseline for coverage)
    // =========================================================================

    /// @notice Simple purchase to establish baseline state
    function action_purchase(
        uint256 actorSeed,
        uint256 qty
    ) external useActor(actorSeed) {
        calls_purchaseOnly++;

        if (game.gameOver()) return;

        qty = bound(qty, 100, 4000);
        (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
        uint256 ticketCost = (priceWei * qty) / 400;
        if (ticketCost == 0 || ticketCost > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchase{value: ticketCost}(
            0, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false
        ) {
            ghost_purchases++;
        } catch {}

        _checkCompositionInvariants();
    }

    // =========================================================================
    // Composition Invariant Checks (run after every action)
    // =========================================================================

    function _checkCompositionInvariants() private {
        _checkPoolSolvency();
        _checkLevelMonotonicity();
        _checkGameOverLatch();
    }

    /// @dev Canonical solvency: Game-held ETH + stETH must cover the full obligation set
    ///      (SolvencyObligations: freeze-window pending buffer in, dead post-game-over pools out).
    function _checkPoolSolvency() private {
        if (SolvencyObligations.backing(game) < SolvencyObligations.obligations(game)) {
            ghost_poolSolvencyViolation++;
        }
    }

    /// @dev Check level only increases
    function _checkLevelMonotonicity() private {
        uint256 currentLevel = game.level();
        if (currentLevel < ghost_lastSeenLevel) {
            ghost_levelDecreased++;
        }
        ghost_lastSeenLevel = currentLevel;
        if (currentLevel > ghost_maxLevel) ghost_maxLevel = currentLevel;
    }

    /// @dev Check gameOver is a one-way latch
    function _checkGameOverLatch() private {
        bool isGameOver = game.gameOver();
        if (isGameOver) {
            ghost_gameOverSeen = true;
        } else if (ghost_gameOverSeen) {
            // gameOver was true, now false -- latch violation
            ghost_gameOverReversed++;
        }
    }
}
