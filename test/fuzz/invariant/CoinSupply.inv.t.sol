// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {VRFHandler} from "../helpers/VRFHandler.sol";
import {GameHandler} from "../handlers/GameHandler.sol";
import {WhaleHandler} from "../handlers/WhaleHandler.sol";
import {BurnieCoin} from "../../../contracts/BurnieCoin.sol";

/// @title CoinSupplyInvariant -- Proves BurnieCoin supply conservation (FUZZ-02)
/// @notice Asserts that totalSupply + vaultAllowance == supplyIncUncirculated
///         and that supplyIncUncirculated never drops below the initial 2M vault seed.
contract CoinSupplyInvariant is DeployProtocol {
    GameHandler public gameHandler;
    VRFHandler public vrfHandler;
    WhaleHandler public whaleHandler;

    /// @dev Initial vault allowance seed (2M BURNIE)
    uint256 constant INITIAL_VAULT_ALLOWANCE = 2_000_000 ether;

    function setUp() public {
        _deployProtocol();

        gameHandler = new GameHandler(game, 10);
        vrfHandler = new VRFHandler(mockVRF, game);
        whaleHandler = new WhaleHandler(game, 5);

        targetContract(address(gameHandler));
        targetContract(address(vrfHandler));
        targetContract(address(whaleHandler));
    }

    /// @notice Supply struct consistency: totalSupply + vaultAllowance == supplyIncUncirculated
    /// @dev This is the critical accounting identity from BurnieCoin's Supply struct.
    ///      If this breaks, token accounting is corrupted.
    function invariant_supplyConsistency() public view {
        uint256 total = coin.totalSupply();
        uint256 allowance = coin.vaultMintAllowance();
        uint256 combined = coin.supplyIncUncirculated();

        assertEq(
            total + allowance,
            combined,
            "BurnieCoin: totalSupply + vaultAllowance != supplyIncUncirculated"
        );
    }

    /// @notice Vault allowance + totalSupply should never drop below initial seed
    /// @dev supplyIncUncirculated starts at 2M (all in vaultAllowance) and only grows
    ///      via creditCoin/mint operations. Burns reduce totalSupply but can increase
    ///      vaultAllowance (vault burns), so the combined value is monotonically non-decreasing.
    function invariant_supplyFloor() public view {
        uint256 combined = coin.supplyIncUncirculated();

        assertGe(
            combined,
            INITIAL_VAULT_ALLOWANCE,
            "BurnieCoin: supplyIncUncirculated dropped below initial 2M seed"
        );
    }

    /// @notice Canary: coin contract is deployed and functional
    function invariant_coinCanary() public view {
        assertTrue(address(coin) != address(0), "Coin not deployed");
        assertTrue(address(coin).code.length > 0, "Coin has no code");
    }
}
