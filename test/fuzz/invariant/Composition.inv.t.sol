// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {ChainCallTally, ChainStallProbe} from "../helpers/ChainCallJudge.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {CompositionHandler} from "../handlers/CompositionHandler.sol";

/// @title CompositionInvariant -- Proves cross-module composition safety
/// @notice Tests that no module interaction sequence corrupts shared state.
///         Uses ghost variables to track pool solvency, level monotonicity,
///         and gameOver latch across random sequences of cross-module operations.
/// @dev Run with FOUNDRY_PROFILE=deep for 1K invariant runs, 256 depth.
///      afterInvariant requires real progress per run (purchases, mineFlips, VRF fulfillments).
///      Composition handler exercises 4 cross-module action sequences (plus a day-warp action):
///      1. purchase then advance (MINT -> ADV)
///      2. whale then purchase (WHALE -> MINT, tests mintPacked_ shared writes)
///      3. advance full cycle (ADV -> JACK -> MINT -> END -> OVER chain)
///      4. simple purchase (baseline)
contract CompositionInvariant is DeployProtocol {
    CompositionHandler public compositionHandler;

    function setUp() public virtual {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        compositionHandler = new CompositionHandler(game, mockVRF, 8);

        targetContract(address(compositionHandler));
    }

    /// @notice Pool solvency must hold after every cross-module operation
    /// @dev obligations = currentPrizePool + nextPrizePool + futurePrizePool + claimablePool
    ///      Must be <= game contract ETH balance at all times.
    function invariant_poolSolvency() public view {
        compositionHandler.judgeCheck("Composition");
        assertEq(
            compositionHandler.ghost_poolSolvencyViolation(),
            0,
            "COMPOSITION BUG: pool obligations exceed game ETH balance"
        );
    }

    /// @notice Game level must monotonically increase (never decrease)
    /// @dev Level transitions only happen in mineFlip() and always increment.
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

    /// @notice Non-vacuity: every run must have actually driven the protocol, not just reverted through it.
    /// @dev Measured minima over 4 x 256 default-depth runs (seed 0xdeadbeef): 88 successful purchases,
    ///      3 whale-pass purchases, 26 successful mineFlips, 6 VRF fulfillments (max level reached was 0 in
    ///      every run: the 8 x 100 ETH actors never fill the level-0 target, so no level floor is asserted).
    ///      Thresholds sit well below those minima: purchases >= 20, mineFlips >= 5, VRF >= 1, whale >= 1.
    ///      A run that ends in game over (at depth 256 a sequence can warp past the VRF deadman while a
    ///      request is unanswered) stops mining once the latch lands, and the latch itself takes a
    ///      successful terminal mineRun; the mineFlip floor applies to runs still live at the end. Runs
    ///      meeting it are counted over the process (vm.setEnv, suite-unique prefix), and once MIN_RUNS
    ///      runs have finished at least one must have.
    uint256 private constant MIN_RUNS = 16;

    function _vacuityPrefix() internal pure virtual returns (string memory) {
        return "COMPOSITION_";
    }

    function _acc(string memory k, uint256 v) internal returns (uint256 total) {
        k = string.concat(_vacuityPrefix(), k);
        total = vm.envOr(k, uint256(0)) + v;
        vm.setEnv(k, vm.toString(total));
    }

    function afterInvariant() public {
        ChainCallTally.tally("Composition", compositionHandler);
        ChainStallProbe.check("Composition", address(game), mockVRF);
        assertGe(compositionHandler.ghost_purchases(), 20, "vacuous: purchases did not succeed");
        assertGe(compositionHandler.ghost_whalePurchases(), 1, "vacuous: no whale pass purchase succeeded");
        assertGe(compositionHandler.ghost_vrfFulfillments(), 1, "vacuous: no VRF word was fulfilled");
        bool mined = compositionHandler.ghost_mineFlips() >= 5;
        if (!game.gameOver()) assertTrue(mined, "vacuous: mineFlip did not make progress");
        uint256 runs = _acc("RUNS", 1);
        uint256 minedRuns = _acc("MINED", mined ? 1 : 0);
        if (runs >= MIN_RUNS) assertGt(minedRuns, 0, "vacuous: no run made mineFlip progress");
    }
}
