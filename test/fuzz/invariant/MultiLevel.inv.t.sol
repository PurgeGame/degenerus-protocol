// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {MultiLevelHandler} from "../handlers/MultiLevelHandler.sol";
import {SolvencyObligations} from "../helpers/SolvencyObligations.sol";

/// @notice Solvency and level history under randomized purchases, VRF and advances.
/// @dev Price is deliberately NOT asserted monotone: each century's milestone price
///      drops from 0.24 ETH to 0.04 ETH at the next level. PriceLookupInvariants covers
///      the actual cyclic curve. The fuzzed walk alone never leaves level 0, so setUp first runs the
///      handler's scripted opening: a fixed real-money, day-by-day drive (one ticket + 60 ETH lootbox
///      purchase, VRF fulfilment and mineFlip cranking per day) that must reach level 10 or setUp
///      fails. GUARANTEED: every run starts at level >= 10 with real pools and queues, solvency and
///      level monotonicity are checked from there. Each trace begins with three fuzz-dependent
///      purchases and verified miner work, then permits unrestricted adversarial actions.
///      NOT guaranteed: the walk raising the level above 10.
contract MultiLevelInvariant is DeployProtocol {
    MultiLevelHandler public mlHandler;

    function setUp() public virtual {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mlHandler = new MultiLevelHandler(game, mockVRF, 15);
        mlHandler.scriptedOpening();
        assertGe(game.currentLvl(), mlHandler.OPENING_LEVEL(), "MultiLevel: the scripted opening must reach its level");
        _targetWalk();
    }

    function _targetWalk() internal {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = mlHandler.walk.selector;
        targetSelector(FuzzSelector({addr: address(mlHandler), selectors: selectors}));
        targetContract(address(mlHandler));
    }

    function invariant_solvencyAcrossLevels() public view {
        assertGe(
            address(game).balance + mockStETH.balanceOf(address(game)),
            SolvencyObligations.obligations(game),
            "MultiLevel: assets must cover obligations"
        );
    }

    function invariant_levelMonotonic() public view {
        assertGe(uint256(game.currentLvl()), mlHandler.ghost_maxLevel(), "MultiLevel: level decreased");
    }

    function test_handlerPurchasesReachTheProtocol() public {
        uint256 before = mlHandler.ghost_totalDeposited();
        mlHandler.purchase(0, 400);
        mlHandler.heavyPurchase(1, 4000);
        assertGt(mlHandler.ghost_totalDeposited(), before, "purchases must succeed");
        invariant_solvencyAcrossLevels();
        invariant_levelMonotonic();
    }

    function test_levelOracleRejectsARewind() public {
        // Inject an observed high-water mark above the current level. The old
        // uint >= 0 assertions passed this state; the history comparison must fail.
        vm.mockCall(address(mlHandler), abi.encodeWithSelector(mlHandler.ghost_maxLevel.selector),
            abi.encode(uint256(game.currentLvl()) + 1));
        vm.expectRevert();
        this.invariant_levelMonotonic();
    }

    /// @notice Non-vacuity of every trace, independent of the random action ordering.
    /// @dev The first walk supplies required activity after the opening snapshots. A trace may
    ///      then legitimately stop buying, time out, and end the game. Required-prefix failures
    ///      are persistent, so fail_on_revert=false cannot turn them into discarded calls.
    function afterInvariant() public view {
        require(!mlHandler.walkFailed(), "MultiLevel: required trace prefix failed");
        assertTrue(mlHandler.walkPrefixComplete(), "MultiLevel: required trace prefix never ran");
        assertEq(mlHandler.walkPrefixPurchases(), 3, "MultiLevel: required purchases did not complete");
        assertEq(mlHandler.walkPrefixWork(), 1, "MultiLevel: required miner work did not complete");
        assertGe(game.currentLvl(), mlHandler.OPENING_LEVEL(), "MultiLevel: level fell below the opening level");
        assertGe(mlHandler.ghost_maxLevel(), mlHandler.OPENING_LEVEL(), "MultiLevel: no level progress recorded");
        assertGe(
            mlHandler.ghost_successfulPurchases() - mlHandler.openingPurchases(), 3,
            "vacuous: the walk made (almost) no successful purchase"
        );
        assertGe(
            mlHandler.ghost_advances() - mlHandler.openingAdvances(), 1,
            "vacuous: the walk never made mineFlip progress"
        );
    }

    function test_singleWarpTraceHasRealActivity() public {
        uint256 bought = mlHandler.ghost_successfulPurchases();
        uint256 advanced = mlHandler.ghost_advances();
        uint256 deposited = mlHandler.ghost_totalDeposited();
        mlHandler.walk(4, type(uint256).max, 0xC0FFEE, 0xBEEF);
        assertEq(mlHandler.ghost_successfulPurchases() - bought, 3, "first warp includes actual purchases");
        assertEq(mlHandler.ghost_advances() - advanced, 1, "first warp includes actual work");
        assertGt(mlHandler.ghost_totalDeposited(), deposited, "prefix spends real ETH");
        afterInvariant();
        invariant_solvencyAcrossLevels();
        invariant_levelMonotonic();
    }

    function test_requiredPurchaseFailurePersists() public {
        bytes memory reason = abi.encodeWithSignature("Error(string)", "forced required purchase failure");
        vm.mockCallRevert(address(game), abi.encodeWithSelector(game.purchaseOrderFor.selector), reason);
        mlHandler.walk(4, 0, 0, 1);
        _assertPrefixFailure(reason);
    }

    function test_requiredMinerFailurePersists() public {
        bytes memory reason = abi.encodeWithSignature("Error(string)", "forced required miner failure");
        vm.mockCallRevert(address(game), abi.encodeWithSelector(game.mineRun.selector), reason);
        mlHandler.walk(4, 0, 0, 1);
        _assertPrefixFailure(reason);
    }

    function test_successWithoutMinerWorkFailsCoverage() public {
        vm.mockCall(address(game), abi.encodeWithSelector(game.mineRun.selector), bytes(""));
        mlHandler.walk(4, 0, 0, 1);
        _assertPrefixFailure(abi.encodeWithSignature("Error(string)", "MultiLevel: prefix miner made no progress"));
    }

    function _assertPrefixFailure(bytes memory reason) private {
        assertTrue(mlHandler.walkFailed(), "required failure must be retained");
        assertFalse(mlHandler.walkPrefixComplete(), "failed prefix cannot count as completed");
        assertEq(mlHandler.walkFailure(), reason, "retain original failure bytes");
        vm.clearMockedCalls();
        // Removing the injected failure cannot turn the same trace into a retry that passes.
        mlHandler.walk(0, 1, 400, 2);
        assertEq(mlHandler.walkFailure(), reason, "later calls cannot hide a prefix failure");
        vm.expectRevert(bytes("MultiLevel: required trace prefix failed"));
        this.afterInvariant();
    }

    function test_laterWarpsRemainUnrestricted() public {
        mlHandler.walk(4, 2, 7, 123);
        uint256 bought = mlHandler.ghost_successfulPurchases();
        uint256 advanced = mlHandler.ghost_advances();
        for (uint256 i; i < 15; ++i) {
            uint256 beforeTime = vm.getBlockTimestamp();
            mlHandler.walk(4, i, i, i);
            assertEq(vm.getBlockTimestamp(), beforeTime + 1 days + 1, "later warps are not repaired");
        }
        assertTrue(game.livenessTriggered(), "adversarial walk can still reach the ending");
        assertEq(mlHandler.ghost_successfulPurchases(), bought, "no automatic later purchases");
        assertEq(mlHandler.ghost_advances(), advanced, "no automatic later mining");
        afterInvariant();
    }

    function test_openingReachesLevelTen() public view virtual {
        assertGe(uint256(game.currentLvl()), mlHandler.OPENING_LEVEL(), "opening level");
        assertGe(mlHandler.ghost_levelTransitions(), mlHandler.OPENING_LEVEL(), "each level was a recorded transition");
        assertLe(mlHandler.openingDays(), mlHandler.OPENING_MAX_DAYS(), "opening bound");
    }
}
