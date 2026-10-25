// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {FSMHandler} from "../handlers/FSMHandler.sol";

/// @title GameFSMInvariant -- Proves game FSM transitions are valid (FUZZ-03)
/// @notice Asserts level monotonicity, gameOver terminality + terminal level freeze, VRF-progress
///         clock monotonicity, and bounded no-brick liveness.
/// @dev The random walk alone never left level 0 (measured: 0 level-ups over 1,285 default-profile runs), so
///      the level properties only ever watched level 0. setUp now plays a real-money scripted opening to
///      OPENING_LEVEL and the handler exposes driveLevelUp (bounded real-money day walk to the next level), so
///      level transitions happen inside the campaign and game over latches at a non-zero level.
///      afterInvariant requires real progress (see there).
contract GameFSMInvariant is DeployProtocol {
    FSMHandler public fsmHandler;

    uint24 internal constant OPENING_LEVEL = 3;
    uint256 internal openingPurchases;
    uint256 internal openingAdvances;
    uint256 internal openingVrf;

    function setUp() public virtual {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        fsmHandler = new FSMHandler(game, mockVRF, 10);
        fsmHandler.scriptedOpening(OPENING_LEVEL);
        assertGe(game.currentLvl(), OPENING_LEVEL, "GameFSM: the scripted opening must reach its level");
        openingPurchases = fsmHandler.ghost_purchases();
        openingAdvances = fsmHandler.ghost_advances();
        openingVrf = fsmHandler.ghost_vrfFulfillments();

        bytes4[] memory sels = new bytes4[](7);
        sels[0] = FSMHandler.purchase.selector;
        sels[1] = FSMHandler.mineFlip.selector;
        sels[2] = FSMHandler.fulfillVrf.selector;
        sels[3] = FSMHandler.recoverAndDrain.selector;
        sels[4] = FSMHandler.warpPastVrfTimeout.selector;
        sels[5] = FSMHandler.warpTime.selector;
        sels[6] = FSMHandler.driveLevelUp.selector;
        targetContract(address(fsmHandler));
        targetSelector(FuzzSelector({addr: address(fsmHandler), selectors: sels}));
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
    ///      A stronger "mineFlip never hard-stalls" ghost was implemented and empirically found
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

    /// @dev Non-vacuity. A single run can legitimately skip a transition (game over can latch before a
    ///      driveLevelUp is drawn), so transitions are accumulated over the process (vm.setEnv, unique FSM_
    ///      prefix) and each must be non-zero once MIN_RUNS runs have completed; campaign-only counts exclude
    ///      the scripted opening. Measured over 1,028 default-profile runs: a campaign level-up in 87% of runs
    ///      (max level 3-8), game over in 97%, post-game-over actions in 97%, a VRF-clock advance in 99% (a run
    ///      that latches game over through the deadman can legitimately process no word).
    uint256 private constant MIN_RUNS = 16;

    function _acc(string memory k, uint256 v) internal virtual returns (uint256 total) {
        total = vm.envOr(k, uint256(0)) + v;
        vm.setEnv(k, vm.toString(total));
    }

    function afterInvariant() public {
        uint256 runs = _acc("FSM_RUNS", 1);
        uint256 purchases = _acc("FSM_purchases", fsmHandler.ghost_purchases() - openingPurchases);
        uint256 advances = _acc("FSM_advances", fsmHandler.ghost_advances() - openingAdvances);
        uint256 vrf = _acc("FSM_vrf", fsmHandler.ghost_vrfFulfillments() - openingVrf);
        uint256 levelUps = _acc("FSM_levelUps", fsmHandler.ghost_levelUps());
        uint256 gameOvers = _acc("FSM_gameOvers", fsmHandler.ghost_everGameOver() ? 1 : 0);
        uint256 postGo = _acc("FSM_postGo", fsmHandler.ghost_postGameOverActions());
        uint256 clock = _acc("FSM_clock", fsmHandler.ghost_vrfClockAdvances());
        if (runs < MIN_RUNS) return;
        assertGt(purchases, 0, "vacuous: no campaign purchase ever succeeded");
        assertGt(advances, 0, "vacuous: no campaign mineFlip ever succeeded");
        assertGt(vrf, 0, "vacuous: no campaign VRF word was ever delivered");
        assertGt(levelUps, 0, "vacuous: the level never rose during a campaign");
        assertGt(gameOvers, 0, "vacuous: no run ever reached game over");
        assertGt(postGo, 0, "vacuous: no action was ever observed after game over");
        assertGt(clock, 0, "vacuous: the VRF clock never advanced");
    }

}
