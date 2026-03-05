// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {CompositionHandler} from "../handlers/CompositionHandler.sol";

/// @title CompositionInvariant -- Proves cross-module composition safety
/// @notice Tests that no module interaction sequence corrupts shared state.
///         Uses ghost variables to track gap bits, pool solvency, level monotonicity,
///         and gameOver latch across random sequences of cross-module operations.
/// @dev Run with FOUNDRY_PROFILE=deep for 1K invariant runs, 256 depth.
///      Composition handler exercises 4 distinct cross-module action sequences:
///      1. purchase then advance (MINT -> ADV)
///      2. whale then purchase (WHALE -> MINT, tests mintPacked_ shared writes)
///      3. advance full cycle (ADV -> JACK -> MINT -> END -> OVER chain)
///      4. simple purchase (baseline)
contract CompositionInvariant is DeployProtocol {
    CompositionHandler public compositionHandler;

    function setUp() public {
        _deployProtocol();

        compositionHandler = new CompositionHandler(game, mockVRF, 8);

        targetContract(address(compositionHandler));
    }

    /// @notice Gap bits (154-159 and 184-227) in mintPacked_ must always be zero
    /// @dev If any setPacked call site writes to gap bits, this catches it.
    ///      Note: bits 160-183 are MINT_STREAK_LAST_COMPLETED (a real field, not gap).
    ///      Ghost counter increments each time gap bits are found nonzero
    ///      after any cross-module action sequence.
    function invariant_gapBitsAlwaysZero() public view {
        assertEq(
            compositionHandler.ghost_gapBitsNonZero(),
            0,
            "COMPOSITION BUG: mintPacked_ gap bits (154-227) found nonzero"
        );
    }

    /// @notice Pool solvency must hold after every cross-module operation
    /// @dev obligations = currentPrizePool + nextPrizePool + futurePrizePool + claimablePool
    ///      Must be <= game contract ETH balance at all times.
    function invariant_poolSolvency() public view {
        assertEq(
            compositionHandler.ghost_poolSolvencyViolation(),
            0,
            "COMPOSITION BUG: pool obligations exceed game ETH balance"
        );
    }

    /// @notice Game level must monotonically increase (never decrease)
    /// @dev Level transitions only happen in advanceGame() and always increment.
    function invariant_levelMonotonicallyIncreasing() public view {
        assertEq(
            compositionHandler.ghost_levelDecreased(),
            0,
            "COMPOSITION BUG: game level decreased"
        );
    }

    /// @notice gameOver is a one-way latch: once true, never false again
    /// @dev If gameOver reverts to false after being true, the game FSM is broken.
    function invariant_gameOverIsOneWayLatch() public view {
        assertEq(
            compositionHandler.ghost_gameOverReversed(),
            0,
            "COMPOSITION BUG: gameOver reverted from true to false"
        );
    }

    /// @notice Canary: composition handler is properly deployed and targeted
    function invariant_compositionCanary() public view {
        assertTrue(
            address(compositionHandler) != address(0),
            "CompositionHandler not deployed"
        );
    }
}
