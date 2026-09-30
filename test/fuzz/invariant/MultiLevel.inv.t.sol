// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {MultiLevelHandler} from "../handlers/MultiLevelHandler.sol";
import {SolvencyObligations} from "../helpers/SolvencyObligations.sol";

/// @notice Solvency and level history under randomized purchases, VRF and advances.
/// @dev Price is deliberately NOT asserted monotone: each century's milestone price
///      drops from 0.24 ETH to 0.04 ETH at the next level. PriceLookupInvariants covers
///      the actual cyclic curve. This random walk does not guarantee reaching level 10.
contract MultiLevelInvariant is DeployProtocol {
    MultiLevelHandler public mlHandler;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mlHandler = new MultiLevelHandler(game, mockVRF, 15);
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
        mlHandler.purchase(0, 400);
        mlHandler.heavyPurchase(1, 4000);
        assertGt(mlHandler.ghost_totalDeposited(), 0, "purchases must succeed");
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
}
