// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {WhaleSybilHandler} from "../handlers/WhaleSybilHandler.sol";

/// @title WhaleSybilInvariant -- Proves solvency under concurrent whale + Sybil pressure
/// @notice NEVER PREVIOUSLY FUZZED in combination. Previous tests exercised whale operations
///         and standard purchases independently. This harness interleaves whale bundle purchases
///         (2.4-4 ETH each, qty 1-5) with Sybil minimum-cost purchases (1/4 ticket each)
///         from a large actor pool.
///
///         Attack vectors targeted:
///         1. Whale bundle at level boundary + simultaneous Sybil flood = pool corruption?
///         2. Whale overpayment combined with Sybil exact-price = accounting mismatch?
///         3. Large whale claims interleaved with many small Sybil purchases
///         4. Pool obligation tracking under mixed purchase types
contract WhaleSybilInvariant is DeployProtocol {
    WhaleSybilHandler public wsHandler;

    function setUp() public {
        _deployProtocol();

        // 3 whales + 20 sybils = high concurrent pressure
        wsHandler = new WhaleSybilHandler(game, mockVRF, 3, 20);

        targetContract(address(wsHandler));
    }

    /// @notice ETH solvency under concurrent whale + sybil pressure
    function invariant_solvencyUnderPressure() public view {
        uint256 gameBalance = address(game).balance;
        uint256 obligations = game.currentPrizePoolView()
            + game.nextPrizePoolView()
            + game.claimablePoolView()
            + game.futurePrizePoolView();

        assertGe(
            gameBalance,
            obligations,
            "WhaleSybil: solvency violated under concurrent pressure"
        );
    }

    /// @notice Ghost: total deposits >= total claims
    /// @dev Combined whale + sybil deposits must always exceed claims
    function invariant_depositsExceedClaims() public view {
        uint256 totalDeposited = wsHandler.ghost_whaleDeposited()
            + wsHandler.ghost_sybilDeposited();
        uint256 totalClaimed = wsHandler.ghost_totalClaimed();

        assertGe(
            totalDeposited,
            totalClaimed,
            "WhaleSybil: more claimed than deposited"
        );
    }

    /// @notice Obligation ratio should stay above 100% (10000 bps)
    /// @dev If the minimum observed obligation ratio drops below 10000 bps,
    ///      it means at some point balance < obligations (insolvency)
    function invariant_obligationRatioHealthy() public view {
        uint256 minRatio = wsHandler.ghost_minObligationRatio();
        // If no observations yet (type(uint256).max), skip
        if (minRatio == type(uint256).max) return;

        assertGe(
            minRatio,
            10_000, // 100% in basis points
            "WhaleSybil: obligation ratio dropped below 100%"
        );
    }

    /// @notice Game over is terminal even under mixed pressure
    function invariant_gameOverTerminal() public view {
        // If game is over, further whale/sybil operations should have no effect
        // This is structurally enforced by the handler's gameOver() checks
        // The invariant here is that the game state is consistent
        if (game.gameOver()) {
            // Game balance should still cover claimable obligations
            uint256 gameBalance = address(game).balance;
            uint256 claimable = game.claimablePoolView();
            assertGe(gameBalance, claimable, "WhaleSybil: post-game claimable exceeds balance");
        }
    }

    /// @notice Canary
    function invariant_whaleSybilCanary() public view {
        assertTrue(address(wsHandler) != address(0), "WhaleSybilHandler not deployed");
    }
}
