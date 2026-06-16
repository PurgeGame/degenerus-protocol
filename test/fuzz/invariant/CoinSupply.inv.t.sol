// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {VRFHandler} from "../helpers/VRFHandler.sol";
import {GameHandler} from "../handlers/GameHandler.sol";
import {WhaleHandler} from "../handlers/WhaleHandler.sol";
import {FLIP} from "../../../contracts/FLIP.sol";

/// @title CoinSupplyInvariant -- Proves FLIP supply conservation (FUZZ-02)
/// @notice Asserts that totalSupply + vaultAllowance == supplyIncUncirculated.
///         There is no supply floor: FLIP deploys with zero supply and zero
///         vault allowance (the initial emission arrives as Coinflip seed
///         stakes), and burns shrink the combined supply.
contract CoinSupplyInvariant is DeployProtocol {
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

    /// @notice Supply struct consistency: totalSupply + vaultAllowance == supplyIncUncirculated
    /// @dev This is the critical accounting identity from FLIP's Supply struct.
    ///      If this breaks, token accounting is corrupted.
    function invariant_supplyConsistency() public view {
        uint256 total = coin.totalSupply();
        uint256 allowance = coin.vaultMintAllowance();
        uint256 combined = coin.supplyIncUncirculated();

        assertEq(
            total + allowance,
            combined,
            "FLIP: totalSupply + vaultAllowance != supplyIncUncirculated"
        );
    }

    /// @notice Canary: coin contract is deployed and functional
    function invariant_coinCanary() public view {
        assertTrue(address(coin) != address(0), "Coin not deployed");
        assertTrue(address(coin).code.length > 0, "Coin has no code");
    }
}
