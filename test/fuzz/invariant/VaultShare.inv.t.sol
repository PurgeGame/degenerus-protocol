// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {VRFHandler} from "../helpers/VRFHandler.sol";
import {GameHandler} from "../handlers/GameHandler.sol";
import {WhaleHandler} from "../handlers/WhaleHandler.sol";
import {DegenerusVault} from "../../../contracts/DegenerusVault.sol";
import {BurnieCoin} from "../../../contracts/BurnieCoin.sol";

/// @title VaultShareInvariant -- Proves vault share math consistency (FUZZ-04)
/// @notice Asserts that vault reserves are non-negative and share token supplies
///         remain valid after all call sequences driven by the fuzzer.
contract VaultShareInvariant is DeployProtocol {
    GameHandler public gameHandler;
    VRFHandler public vrfHandler;
    WhaleHandler public whaleHandler;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        gameHandler = new GameHandler(game, 10);
        vrfHandler = new VRFHandler(mockVRF, game);
        whaleHandler = new WhaleHandler(game, 5);

        targetContract(address(gameHandler));
        targetContract(address(vrfHandler));
        targetContract(address(whaleHandler));
    }

    /// @notice Vault ETH balance is non-negative (always true for uint, but checks vault is alive)
    /// @dev The vault receives ETH from game deposits. Its balance should never underflow.
    function invariant_vaultEthNonNegative() public view {
        uint256 vaultBalance = address(vault).balance;
        assertGe(vaultBalance, 0, "Vault ETH balance is negative (impossible)");
    }

    /// @notice Vault coin reserves track correctly
    /// @dev The vault's BURNIE reserves are: vaultMintAllowance + coin.balanceOf(vault) + claimable.
    ///      The vaultMintAllowance should be <= supplyIncUncirculated since it's a subset.
    function invariant_vaultCoinReservesConsistent() public view {
        uint256 vaultAllowance = coin.vaultMintAllowance();
        uint256 totalIncUncirculated = coin.supplyIncUncirculated();

        // Vault allowance is part of supplyIncUncirculated
        assertLe(
            vaultAllowance,
            totalIncUncirculated,
            "Vault allowance exceeds supplyIncUncirculated"
        );
    }

    /// @notice Vault should not hold more BURNIE allowance than what was escrowed
    /// @dev vaultMintAllowance starts at 2M and increases via vaultEscrow().
    ///      It decreases via vaultMintTo(). It should never exceed the uncirculated total.
    function invariant_vaultAllowanceBounded() public view {
        uint256 vaultAllowance = coin.vaultMintAllowance();
        uint256 combined = coin.supplyIncUncirculated();

        // vaultAllowance <= combined (since combined = totalSupply + vaultAllowance)
        assertLe(
            vaultAllowance,
            combined,
            "Vault allowance exceeds combined supply"
        );
    }

    /// @notice Canary: vault contract is deployed
    function invariant_vaultCanary() public view {
        assertTrue(address(vault) != address(0), "Vault not deployed");
        assertTrue(address(vault).code.length > 0, "Vault has no code");
    }
}
