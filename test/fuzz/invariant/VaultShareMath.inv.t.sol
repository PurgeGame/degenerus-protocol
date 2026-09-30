// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {VRFHandler} from "../helpers/VRFHandler.sol";
import {VaultHandler} from "../handlers/VaultHandler.sol";
import {GameHandler} from "../handlers/GameHandler.sol";
import {DegenerusVault} from "../../../contracts/DegenerusVault.sol";
import {FLIP} from "../../../contracts/FLIP.sol";
import {SolvencyObligations} from "../helpers/SolvencyObligations.sol";

/// @title VaultShareMathInvariant -- Proves vault share math consistency under deposit/withdraw
/// @notice Drives partial and full burns; reconciles both share supplies against
///         successful burns and refill counts, and checks game solvency and ETH outflows.
contract VaultShareMathInvariant is DeployProtocol {
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000_000 ether;
    VaultHandler public vaultHandler;
    GameHandler public gameHandler;
    VRFHandler public vrfHandler;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        // Game handler drives purchases (ETH flows into protocol, eventually to vault via jackpots)
        gameHandler = new GameHandler(game, 10);
        vrfHandler = new VRFHandler(mockVRF, game);

        // Creator in Foundry context is address(this) = the invariant test contract
        vaultHandler = new VaultHandler(
            game,
            vault,
            coin,
            mockVRF,
            address(this), // creator
            5
        );

        targetContract(address(gameHandler));
        targetContract(address(vrfHandler));
        targetContract(address(vaultHandler));
    }

    /// @notice Burned shares disappear; full burns mint exactly the refill supply.
    function invariant_shareSupplyReconciles() public view {
        assertEq(vaultHandler.ethShare().totalSupply() + vaultHandler.ghost_ethBurned(),
            INITIAL_SUPPLY * (1 + vaultHandler.ghost_ethRefills()), "DGVE burn/refill accounting");
        assertEq(vaultHandler.flipShare().totalSupply() + vaultHandler.ghost_coinBurned(),
            INITIAL_SUPPLY * (1 + vaultHandler.ghost_coinRefills()), "DGVF burn/refill accounting");
        // These handlers never transfer shares. Supply and the sole holder must agree.
        assertEq(vaultHandler.ethShare().balanceOf(address(this)), vaultHandler.ethShare().totalSupply());
        assertEq(vaultHandler.flipShare().balanceOf(address(this)), vaultHandler.flipShare().totalSupply());
    }

    /// @notice Ghost: total ETH received from vault burns <= total ETH deposited into protocol
    /// @dev Vault receives ETH from game jackpots. Total claims from vault cannot exceed
    ///      total ETH ever deposited into the game.
    function invariant_vaultEthClaimsLessThanDeposits() public view {
        uint256 totalGameDeposits = gameHandler.ghost_totalDeposited() + vaultHandler.ghost_totalDeposited();
        uint256 totalVaultEthOut = vaultHandler.ghost_ethReceived();

        assertGe(
            totalGameDeposits,
            totalVaultEthOut,
            "VaultShareMath: vault ETH claims exceed total game deposits"
        );
    }

    /// @notice ETH solvency invariant still holds under vault operations
    /// @dev The game contract must remain solvent even while vault is burning shares
    function invariant_gameSolvencyUnderVaultOps() public view {
        uint256 gameBalance = address(game).balance + mockStETH.balanceOf(address(game));
        // Canonical obligation set (pending buffer in, dead post-GO pools out) -- SolvencyObligations.
        uint256 obligations = SolvencyObligations.obligations(game);

        assertGe(
            gameBalance,
            obligations,
            "VaultShareMath: game solvency violated under vault operations"
        );
    }

    function test_partialAndFullBurnsAreExercised() public {
        vaultHandler.burnEth(1);
        vaultHandler.burnCoin(1);
        invariant_shareSupplyReconciles();
        vaultHandler.burnEth(0); // explicit full-burn branch
        vaultHandler.burnCoin(0);
        assertEq(vaultHandler.ghost_burnEthSuccess(), 2);
        assertEq(vaultHandler.ghost_burnCoinSuccess(), 2);
        assertEq(vaultHandler.ghost_ethRefills(), 1);
        assertEq(vaultHandler.ghost_coinRefills(), 1);
        invariant_shareSupplyReconciles();
    }

    function test_shareOracleRejectsMissingBurn() public {
        vaultHandler.burnEth(1);
        assertEq(vaultHandler.ghost_burnEthSuccess(), 1);
        vm.mockCall(address(vaultHandler.ethShare()),
            abi.encodeWithSelector(vaultHandler.ethShare().totalSupply.selector), abi.encode(INITIAL_SUPPLY));
        vm.expectRevert();
        this.invariant_shareSupplyReconciles();
    }
}
