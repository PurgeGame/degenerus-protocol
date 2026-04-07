// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";

/// @title CompositionHandler -- Handler for cross-module composition invariant tests
/// @notice Exercises cross-module state transitions and tracks ghost variables
///         for composition safety invariants (gap bits, pool solvency, level monotonicity).
/// @dev Uses FOUNDRY_PROFILE=deep for 1K invariant runs.
contract CompositionHandler is Test {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;

    // --- Ghost variables for composition invariants ---
    uint256 public ghost_gapBitsNonZero;
    uint256 public ghost_poolSolvencyViolation;
    uint256 public ghost_levelDecreased;
    bool public ghost_gameOverSeen;
    uint256 public ghost_gameOverReversed;
    uint256 public ghost_lastSeenLevel;

    // --- Call counters ---
    uint256 public calls_purchaseThenAdvance;
    uint256 public calls_whaleThenPurchase;
    uint256 public calls_advanceFullCycle;
    uint256 public calls_purchaseOnly;

    // --- Actor management ---
    address[] public actors;
    address internal currentActor;

    // --- Constants ---
    // mintPacked_ is at storage slot 10 (from forge inspect)
    uint256 private constant MINT_PACKED_SLOT = 10;
    // Gap bits are in TWO ranges (NOT continuous):
    //   Gap 1: bits 154-159 (6 bits) -- between WHALE_BUNDLE_TYPE(152-153) and MINT_STREAK_LAST_COMPLETED(160-183)
    //   Gap 2: bits 215-227 (13 bits) -- between AFFILIATE_BONUS_POINTS(209-214) and LEVEL_UNITS(228-243)
    // Real fields between gaps: MINT_STREAK(160-183), DEITY_PASS(184), AFFILIATE_BONUS_LEVEL(185-208), AFFILIATE_BONUS_POINTS(209-214)
    uint256 private constant GAP1_SHIFT = 154;
    uint256 private constant GAP1_MASK = (uint256(1) << 6) - 1;   // 6 bits: 154-159
    uint256 private constant GAP2_SHIFT = 215;
    uint256 private constant GAP2_MASK = (uint256(1) << 13) - 1;  // 13 bits: 215-227

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

    /// @notice Purchase tickets then call advanceGame -- tests MINT->ADV composition
    function action_purchaseThenAdvance(
        uint256 actorSeed,
        uint256 qty
    ) external useActor(actorSeed) {
        calls_purchaseThenAdvance++;

        if (game.gameOver()) return;

        qty = bound(qty, 100, 2000);

        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 ticketCost = (priceWei * qty) / 400;
        if (ticketCost == 0 || ticketCost > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchase{value: ticketCost}(
            currentActor, qty, 0, bytes32(0), MintPaymentKind.DirectEth
        ) {} catch {}

        // Now advance
        vm.prank(currentActor);
        try game.advanceGame() {} catch {}

        _checkCompositionInvariants(currentActor);
    }

    // =========================================================================
    // Action: Whale Bundle then Purchase (WHALE then MINT for same player)
    // =========================================================================

    /// @notice Whale bundle then purchase -- tests mintPacked_ shared writes
    function action_whaleThenPurchase(
        uint256 actorSeed,
        uint256 qty
    ) external useActor(actorSeed) {
        calls_whaleThenPurchase++;

        if (game.gameOver()) return;

        // Try whale bundle first
        uint256 whaleCost = 2.4 ether;
        if (whaleCost <= currentActor.balance) {
            vm.prank(currentActor);
            try game.purchaseWhaleBundle{value: whaleCost}(currentActor, 1) {} catch {}
        }

        // Then purchase tickets
        qty = bound(qty, 100, 1000);
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 ticketCost = (priceWei * qty) / 400;
        if (ticketCost > 0 && ticketCost <= currentActor.balance) {
            vm.prank(currentActor);
            try game.purchase{value: ticketCost}(
                currentActor, qty, 0, bytes32(0), MintPaymentKind.DirectEth
            ) {} catch {}
        }

        _checkCompositionInvariants(currentActor);
    }

    // =========================================================================
    // Action: Advance Full Cycle (ADV -> JACK -> MINT -> END -> OVER chain)
    // =========================================================================

    /// @notice Call advanceGame multiple times to drive through orchestration sequence
    function action_advanceFullCycle(
        uint256 actorSeed
    ) external useActor(actorSeed) {
        calls_advanceFullCycle++;

        if (game.gameOver()) return;

        // First ensure actor has purchased today (daily gate)
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 ticketCost = (priceWei * 100) / 400;
        if (ticketCost > 0 && ticketCost <= currentActor.balance) {
            vm.prank(currentActor);
            try game.purchase{value: ticketCost}(
                currentActor, 100, 0, bytes32(0), MintPaymentKind.DirectEth
            ) {} catch {}
        }

        // Try to advance 3 times (may trigger VRF, jackpot, etc.)
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(currentActor);
            try game.advanceGame() {} catch {}
        }

        // Try to fulfill VRF if pending
        uint256 reqId = vrf.lastRequestId();
        if (reqId != 0) {
            (, , bool fulfilled) = vrf.pendingRequests(reqId);
            if (!fulfilled) {
                try vrf.fulfillRandomWords(reqId, uint256(keccak256(abi.encode(block.timestamp, actorSeed)))) {} catch {}
            }
        }

        // Advance again after VRF
        vm.prank(currentActor);
        try game.advanceGame() {} catch {}

        _checkCompositionInvariants(currentActor);
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
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 ticketCost = (priceWei * qty) / 400;
        if (ticketCost == 0 || ticketCost > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchase{value: ticketCost}(
            currentActor, qty, 0, bytes32(0), MintPaymentKind.DirectEth
        ) {} catch {}

        _checkCompositionInvariants(currentActor);
    }

    // =========================================================================
    // Composition Invariant Checks (run after every action)
    // =========================================================================

    function _checkCompositionInvariants(address player) private {
        _checkGapBits(player);
        _checkPoolSolvency();
        _checkLevelMonotonicity();
        _checkGameOverLatch();
    }

    /// @dev Check mintPacked_[player] gap bits (154-159 and 184-227) are zero
    function _checkGapBits(address player) private {
        bytes32 slot = keccak256(abi.encode(player, MINT_PACKED_SLOT));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 gap1 = (packed >> GAP1_SHIFT) & GAP1_MASK;
        uint256 gap2 = (packed >> GAP2_SHIFT) & GAP2_MASK;
        if (gap1 != 0 || gap2 != 0) {
            ghost_gapBitsNonZero++;
        }
    }

    /// @dev Check pool solvency: obligations <= balance
    function _checkPoolSolvency() private {
        uint256 gameBalance = address(game).balance;
        uint256 obligations = game.currentPrizePoolView()
            + game.nextPrizePoolView()
            + game.futurePrizePoolView()
            + game.claimablePoolView();
        if (obligations > gameBalance) {
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
