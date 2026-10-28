// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

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

    function setUp() public virtual {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        // 3 whales + 20 sybils = high concurrent pressure
        wsHandler = new WhaleSybilHandler(game, mockVRF, 3, 20);

        _targetWalk();
    }

    function _targetWalk() internal {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = wsHandler.walk.selector;
        targetSelector(FuzzSelector({addr: address(wsHandler), selectors: selectors}));
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

    /// @notice Opening Game backing plus subsequent deposits covers the handler's claims.
    /// @dev A Degenesis opening contains real deposits from other actors before the
    ///      handler starts. Winners can claim those prizes as well as newly deposited funds.
    ///      The independent live-obligation and post-game solvency assertions stay unchanged.
    function invariant_depositsExceedClaims() public view {
        uint256 totalDeposited = wsHandler.ghost_whaleDeposited()
            + wsHandler.ghost_sybilDeposited();
        uint256 totalClaimed = wsHandler.ghost_totalClaimed();

        assertGe(
            wsHandler.ghost_initialBacking() + totalDeposited,
            totalClaimed,
            "WhaleSybil: claims exceed opening backing plus deposits"
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

    /// @dev The first walk guarantees real mixed pressure after setup, with failures retained.
    ///      Per-trace minima remain four sybil purchases, one mineFlip and an observed obligation
    ///      ratio; the required prefix also buys a whale pass. Later random actions are unrestricted.
    ///      Accumulated over fuzz traces (unique WS_ prefix): whale passes and VRF words from
    ///      16 runs, paying claims from 32, a game over from 512. Ordinary regression tests do
    ///      not contribute to these process-global aggregates.
    function _acc(string memory k, uint256 v) internal virtual returns (uint256 total) {
        total = vm.envOr(k, uint256(0)) + v;
        vm.setEnv(k, vm.toString(total));
    }

    function afterInvariant() public {
        _assertTraceCoverage();
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

    function _assertTraceCoverage() internal view {
        require(!wsHandler.walkFailed(), "WhaleSybil: required trace prefix failed");
        assertTrue(wsHandler.walkPrefixComplete(), "WhaleSybil: required trace prefix never ran");
        assertEq(wsHandler.walkPrefixSybils(), 4, "WhaleSybil: required sybil activity missing");
        assertEq(wsHandler.walkPrefixWhales(), 1, "WhaleSybil: required whale activity missing");
        assertEq(wsHandler.walkPrefixWork(), 1, "WhaleSybil: required miner activity missing");
        assertGe(wsHandler.ghost_sybilSuccessful(), 4, "vacuous: sybil purchases did not succeed");
        assertGe(wsHandler.ghost_advances(), 1, "vacuous: mineFlip never succeeded in this run");
        assertTrue(wsHandler.ghost_minObligationRatio() != type(uint256).max, "vacuous: obligation ratio never observed");
    }

    function test_singleWarpTraceHasRealMixedActivity() public {
        assertEq(wsHandler.ghost_sybilSuccessful(), 0, "setup is not counted");
        assertEq(wsHandler.ghost_whaleSuccessful(), 0, "setup is not counted");
        // Preserve the original minimized trace's warp argument behind the required prefix.
        wsHandler.walk(5, 7, 21823842782624324229, 0xBEEF);
        assertEq(wsHandler.ghost_sybilSuccessful(), 4);
        assertEq(wsHandler.ghost_whaleSuccessful(), 1);
        assertEq(wsHandler.ghost_advances(), 1);
        _assertTraceCoverage();
        invariant_solvencyUnderPressure();
        invariant_depositsExceedClaims();
        invariant_obligationRatioHealthy();
    }

    function test_requiredSybilFailurePersists() public {
        bytes memory reason = abi.encodeWithSignature("Error(string)", "forced required sybil failure");
        vm.mockCallRevert(address(game), abi.encodeWithSelector(game.purchaseOrderFor.selector), reason);
        wsHandler.walk(5, 0, 0, 1);
        _assertPrefixFailure(reason);
    }

    function test_requiredWhaleFailurePersists() public {
        bytes memory reason = abi.encodeWithSignature("Error(string)", "forced required whale failure");
        vm.mockCallRevert(address(game), abi.encodeWithSelector(game.purchaseWhalePass.selector), reason);
        wsHandler.walk(5, 0, 0, 1);
        _assertPrefixFailure(reason);
    }

    function test_requiredMinerFailurePersists() public {
        bytes memory reason = abi.encodeWithSignature("Error(string)", "forced required miner failure");
        vm.mockCallRevert(address(game), abi.encodeWithSelector(game.mineRun.selector), reason);
        wsHandler.walk(5, 0, 0, 1);
        _assertPrefixFailure(reason);
    }

    function test_successWithoutMinerWorkFailsCoverage() public {
        vm.mockCall(address(game), abi.encodeWithSelector(game.mineRun.selector), bytes(""));
        wsHandler.walk(5, 0, 0, 1);
        _assertPrefixFailure(abi.encodeWithSignature("Error(string)", "WhaleSybil: prefix miner made no progress"));
    }

    function _assertPrefixFailure(bytes memory reason) private {
        assertTrue(wsHandler.walkFailed(), "required failure must be retained");
        assertFalse(wsHandler.walkPrefixComplete(), "failed prefix cannot count as completed");
        assertEq(wsHandler.walkFailure(), reason, "retain original failure bytes");
        vm.clearMockedCalls();
        wsHandler.walk(1, 1, 0, 2);
        assertEq(wsHandler.walkFailure(), reason, "later calls cannot hide a prefix failure");
        vm.expectRevert(bytes("WhaleSybil: required trace prefix failed"));
        this.afterInvariant();
    }

    function test_laterWarpsRemainUnrestricted() public {
        wsHandler.walk(5, 2, 2 days, 123);
        uint256 sybilBuys = wsHandler.ghost_sybilSuccessful();
        uint256 whaleBuys = wsHandler.ghost_whaleSuccessful();
        uint256 advanced = wsHandler.ghost_advances();
        for (uint256 i; i < 8; ++i) {
            uint256 beforeTime = vm.getBlockTimestamp();
            wsHandler.walk(5, i, 2 days, i);
            assertEq(vm.getBlockTimestamp(), beforeTime + 2 days, "later warps are not repaired");
        }
        assertTrue(game.livenessTriggered(), "adversarial walk can still reach the ending");
        assertEq(wsHandler.ghost_sybilSuccessful(), sybilBuys, "no automatic later sybil purchases");
        assertEq(wsHandler.ghost_whaleSuccessful(), whaleBuys, "no automatic later whale purchases");
        assertEq(wsHandler.ghost_advances(), advanced, "no automatic later mining");
        _assertTraceCoverage();
    }
}
