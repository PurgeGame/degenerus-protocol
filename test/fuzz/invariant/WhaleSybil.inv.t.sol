// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {WhaleSybilHandler} from "../handlers/WhaleSybilHandler.sol";
import {SolvencyObligations} from "../helpers/SolvencyObligations.sol";

/// @title WhaleSybilInvariant -- Proves solvency under concurrent whale + Sybil pressure
/// @notice NEVER PREVIOUSLY FUZZED in combination. Previous tests exercised whale operations
///         and standard purchases independently. This harness interleaves whale pass purchases
///         (2.4-4 ETH each, qty 1-5) with Sybil minimum-cost purchases (1/4 ticket each)
///         from a large actor pool.
///
///         Attack vectors targeted:
///         1. Whale pass + simultaneous Sybil flood = pool corruption? (The campaign stays at level 0:
///            measured max level 0 over 1,285 default-profile runs, so level-boundary whale pricing is
///            NOT exercised here; the deep-level walk is MultiLevel's.)
///         2. Whale overpayment combined with Sybil exact-price = accounting mismatch?
///         3. Large whale claims interleaved with many small Sybil purchases
///         4. Pool obligation tracking under mixed purchase types
contract WhaleSybilInvariant is DeployProtocol {
    WhaleSybilHandler public wsHandler;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        // 3 whales + 20 sybils = high concurrent pressure
        wsHandler = new WhaleSybilHandler(game, mockVRF, 3, 20);

        targetContract(address(wsHandler));
    }

    /// @notice ETH + stETH backing covers obligations under concurrent whale + sybil pressure
    function invariant_solvencyUnderPressure() public view {
        uint256 gameBacking = SolvencyObligations.backing(game);
        // Canonical obligation set (pending buffer in, dead post-GO pools out) -- SolvencyObligations.
        uint256 obligations = SolvencyObligations.obligations(game);

        assertGe(
            gameBacking,
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
    ///      it means at some point ETH + stETH backing < obligations (insolvency)
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
    /// @dev Only active once game over latches, which the 2-day warps reach rarely (24 of 1,285 measured
    ///      runs); afterInvariant requires it to have been reached once 512 runs have accumulated.
    function invariant_gameOverTerminal() public view {
        // If game is over, further whale/sybil operations should have no effect
        // This is structurally enforced by the handler's gameOver() checks
        // The invariant here is that the game state is consistent
        if (game.gameOver()) {
            // Remaining ETH + stETH backing must cover claimable obligations.
            uint256 gameBacking = SolvencyObligations.backing(game);
            uint256 claimable = game.claimablePoolView();
            assertGe(gameBacking, claimable, "WhaleSybil: post-game claimable exceeds backing");
        }
    }

    /// @dev Non-vacuity. Measured minima over
    ///      1,285 default-profile runs: 9 successful sybil purchases and 1 successful mineFlip per run; whale
    ///      passes, VRF words and paying claims can be absent from a single run (45, 48 and 970 runs had none),
    ///      and game over latched in only 24 runs. Per run: sybil purchases >= 4 and mineFlip >= 1, and the
    ///      obligation ratio must have been observed. Accumulated over the process (unique WS_ prefix): whale
    ///      passes and VRF words from 16 runs, paying claims from 32, a game over from 512.
    function _acc(string memory k, uint256 v) private returns (uint256 total) {
        total = vm.envOr(k, uint256(0)) + v;
        vm.setEnv(k, vm.toString(total));
    }

    function afterInvariant() public {
        assertGe(wsHandler.ghost_sybilSuccessful(), 4, "vacuous: sybil purchases did not succeed");
        assertGe(wsHandler.ghost_advances(), 1, "vacuous: mineFlip never succeeded in this run");
        assertTrue(wsHandler.ghost_minObligationRatio() != type(uint256).max, "vacuous: obligation ratio never observed");
        uint256 runs = _acc("WS_RUNS", 1);
        uint256 whales = _acc("WS_whales", wsHandler.ghost_whaleSuccessful());
        uint256 vrf = _acc("WS_vrf", wsHandler.ghost_vrfFulfillments());
        uint256 claims = _acc("WS_claims", wsHandler.ghost_claims());
        uint256 gameOvers = _acc("WS_gameOvers", game.gameOver() ? 1 : 0);
        if (runs < 16) return;
        assertGt(whales, 0, "vacuous: no whale pass purchase ever succeeded");
        assertGt(vrf, 0, "vacuous: no VRF word was ever fulfilled");
        if (runs < 32) return;
        assertGt(claims, 0, "vacuous: no whale claim ever paid out");
        if (runs < 512) return;
        assertGt(gameOvers, 0, "vacuous: no run ever reached game over");
    }

}
