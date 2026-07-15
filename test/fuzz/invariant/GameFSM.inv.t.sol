// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {FSMHandler} from "../handlers/FSMHandler.sol";

/// @title GameFSMInvariant -- Proves game FSM transitions are valid (FUZZ-03)
/// @notice Asserts level monotonicity, gameOver terminality + terminal level freeze, VRF-progress
///         clock monotonicity, and bounded no-brick liveness.
contract GameFSMInvariant is DeployProtocol {
    FSMHandler public fsmHandler;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        fsmHandler = new FSMHandler(game, mockVRF, 10);

        targetContract(address(fsmHandler));
    }

    /// @notice Level monotonicity: level never decreases
    /// @dev The FSMHandler tracks every level decrease. This count must be 0.
    function invariant_levelMonotonic() public view {
        assertEq(
            fsmHandler.ghost_levelDecreaseCount(),
            0,
            "GameFSM: level decreased -- monotonicity violated"
        );
    }

    /// @notice gameOver is terminal: once true, never reverts to false
    /// @dev The FSMHandler tracks any gameOver -> !gameOver transition. Count must be 0.
    function invariant_gameOverTerminal() public view {
        assertEq(
            fsmHandler.ghost_gameOverRevival(),
            0,
            "GameFSM: gameOver revived -- terminality violated"
        );
    }

    /// @notice Terminal freeze: once gameOver latches, `level` never changes again.
    /// @dev Genuinely falsifiable and strictly stronger than the two invariants above:
    ///      levelMonotonic still permits a post-gameover level INCREASE and gameOverTerminal only
    ///      checks gameOver stays true, so a bug that bumped `level` during the post-gameover
    ///      multi-tx final-sweep sequence would pass both yet fail here. `level` is only written
    ///      pre-gameover (at RNG-request time), so the terminal level is fixed. Replaces the former
    ///      `assertTrue(true)` no-op: "exactly one of PURCHASE/JACKPOT/GAMEOVER active" was a
    ///      tautology (GAMEOVER := gameOver absorbs the gameOver case, and PURCHASE/JACKPOT are the
    ///      complementary halves of the jackpotPhase bool), so it could never fail.
    function invariant_levelFrozenAfterGameOver() public view {
        assertEq(
            fsmHandler.ghost_levelChangedAfterGameOver(),
            0,
            "GameFSM: level mutated after gameOver -- terminal freeze violated"
        );
    }

    /// @notice Liveness clock: the VRF-progress stamp (lastVrfProcessed()) is monotone
    ///         non-decreasing -- it never rewinds.
    /// @dev This is the SOUND no-brick-adjacent liveness property. lastVrfProcessed() is written
    ///      only as `uint48(block.timestamp)` at VRF processing points, so it can only move forward;
    ///      a regression signals corrupted liveness bookkeeping -- and it is exactly this stamp the
    ///      governance / VRF-death deadman stall detectors read to decide whether the game is frozen,
    ///      so a rewind here would blind the anti-freeze machinery. Genuinely falsifiable (proven:
    ///      injecting a backward write flags it) and non-flaky (the stamp cannot legitimately
    ///      decrease). The FSMHandler's recoverAndDrain crank drives the game through many
    ///      request/fulfill/unlock cycles so this stamp actually advances (non-vacuous).
    ///
    ///      A stronger "advanceGame never hard-stalls" ghost was implemented and empirically found
    ///      FLAKY: within-day / backlog drain makes real progress that is invisible through the
    ///      exposed views, so a bounded crank false-positives on a large legitimate backlog and no
    ///      sound threshold-free version is wireable without a contract-exposed progress counter. It
    ///      was therefore removed; recoverAndDrain remains as a coverage driver only.
    function invariant_vrfClockMonotone() public view {
        assertEq(
            fsmHandler.ghost_vrfClockRegressions(),
            0,
            "GameFSM: lastVrfProcessed() rewound -- VRF clock regressed"
        );
    }

    /// @notice Canary: game is deployed and level is accessible.
    function invariant_fsmCanary() public view {
        assertTrue(address(game) != address(0), "Game not deployed");
        // Level is uint24, so always >= 0, but verify it's accessible
        game.level();
    }
}
