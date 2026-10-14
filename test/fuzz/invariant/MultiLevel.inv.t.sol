// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

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
///      level monotonicity are checked from there, and afterInvariant requires the walk to still
///      purchase and mineFlip. NOT guaranteed: the walk raising the level above 10.
contract MultiLevelInvariant is DeployProtocol {
    MultiLevelHandler public mlHandler;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mlHandler = new MultiLevelHandler(game, mockVRF, 15);
        mlHandler.scriptedOpening();
        assertGe(game.level(), mlHandler.OPENING_LEVEL(), "MultiLevel: the scripted opening must reach its level");
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
        assertGe(uint256(game.level()), mlHandler.ghost_maxLevel(), "MultiLevel: level decreased");
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
            abi.encode(uint256(game.level()) + 1));
        vm.expectRevert();
        this.invariant_levelMonotonic();
    }

    /// @notice Non-vacuity of every run, on top of the opening guarantee.
    /// @dev Measured minima over 4 x 256 default-depth runs (seed 0xdeadbeef), after the opening: 12
    ///      successful walk purchases and 2 successful walk mineFlips (the walk alone ends 1 VRF word
    ///      past the opening, so VRF is not asserted per run). Thresholds: purchases >= 3, mineFlips >= 1.
    ///      The walk never raised the level beyond the opening's (max level 10 in every run): the level
    ///      floor is the opening's, and the walk is not claimed to advance further.
    function afterInvariant() public view {
        assertGe(game.level(), mlHandler.OPENING_LEVEL(), "MultiLevel: level fell below the opening level");
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

    function test_openingReachesLevelTen() public view {
        assertGe(uint256(game.level()), mlHandler.OPENING_LEVEL(), "opening level");
        assertGe(mlHandler.ghost_levelTransitions(), mlHandler.OPENING_LEVEL(), "each level was a recorded transition");
        assertLe(mlHandler.openingDays(), mlHandler.OPENING_MAX_DAYS(), "opening bound");
    }
}
