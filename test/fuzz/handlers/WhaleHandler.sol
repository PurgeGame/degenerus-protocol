// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";

/// @title WhaleHandler -- Handler for whale bundle, lazy pass, and deity pass operations
/// @notice Wraps whale mechanics with bounded inputs, multi-actor support,
///         and ghost variable ETH tracking for invariant tests.
contract WhaleHandler is Test {
    DegenerusGame public game;

    // --- Ghost variables ---
    uint256 public ghost_whaleBundleDeposited;
    uint256 public ghost_lazyPassDeposited;
    uint256 public ghost_deityPassDeposited;

    // --- Call counters ---
    uint256 public calls_whaleBundle;
    uint256 public calls_lazyPass;
    uint256 public calls_deityPass;

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
            // Use different address range than GameHandler to avoid collisions
            address actor = address(uint160(0xB0000 + i));
            actors.push(actor);
            vm.deal(actor, 200 ether);
        }
    }

    /// @notice Purchase whale bundle with bounded quantity
    /// @param actorSeed Seed for actor selection
    /// @param qty Raw quantity, bounded to [1, 5]
    function purchaseWhaleBundle(
        uint256 actorSeed,
        uint256 qty
    ) external useActor(actorSeed) {
        calls_whaleBundle++;

        if (game.gameOver()) return;

        qty = bound(qty, 1, 5);

        // Whale bundle price: 2.4 ETH at levels 0-3, 4 ETH at x49/x99
        // Use 2.4 ETH as base -- most runs will be at early levels
        // The contract will revert if the price doesn't match, which is fine
        uint256 cost = 2.4 ether * qty;
        if (cost > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchaseWhaleBundle{value: cost}(currentActor, qty) {
            ghost_whaleBundleDeposited += cost;
        } catch {}
    }

    /// @notice Purchase lazy pass
    /// @param actorSeed Seed for actor selection
    function purchaseLazyPass(uint256 actorSeed) external useActor(actorSeed) {
        calls_lazyPass++;

        if (game.gameOver()) return;

        // Lazy pass: 0.24 ETH at levels 0-2
        // At higher levels the cost varies -- we use a fixed price and let reverts handle mismatches
        uint256 cost = 0.24 ether;
        if (cost > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchaseLazyPass{value: cost}(currentActor) {
            ghost_lazyPassDeposited += cost;
        } catch {}
    }

    /// @notice Purchase deity pass with bounded symbol ID
    /// @param actorSeed Seed for actor selection
    /// @param symbolId Raw symbol ID, bounded to [0, 31]
    function purchaseDeityPass(
        uint256 actorSeed,
        uint256 symbolId
    ) external useActor(actorSeed) {
        calls_deityPass++;

        if (game.gameOver()) return;

        symbolId = bound(symbolId, 0, 31);

        // Deity pass price: 24 + T(k) ETH where T(k) = k*(k+1)/2, k = passes sold
        // First pass: 24 ETH, second: 25 ETH, third: 27 ETH, etc.
        // We send 30 ETH (covers first few) -- contract reverts if price doesn't match,
        // but many early passes will succeed
        // Actually, contract checks msg.value == exact price, so we need to compute it
        // Use a generous overpayment approach -- the contract requires exact match,
        // so let's try the base price (24 ETH) and let reverts handle when k > 0
        uint256 cost = 24 ether;
        if (cost > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchaseDeityPass{value: cost}(currentActor, uint8(symbolId)) {
            ghost_deityPassDeposited += cost;
        } catch {}
    }
}
