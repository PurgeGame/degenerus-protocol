// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title FlipVaultAllowanceSaturation
/// @notice Mints and transfers into the Vault add to its virtual 128-bit mint allowance. The add
///         saturates at uint128 max, so it never wraps to a small value that would starve a
///         later `vaultMintTo` (the DGVE `burnCoin` payout).
contract FlipVaultAllowanceSaturation is DeployProtocol {
    uint256 internal constant U128_MAX = type(uint128).max;
    address internal constant GAME = ContractAddresses.GAME;
    address internal constant VAULT = ContractAddresses.VAULT;
    address internal alice = address(0xA11CE);

    function setUp() public {
        _deployProtocol();
    }

    function test_mintToVaultSaturates() public {
        vm.startPrank(GAME);
        coin.mintForGame_g152734(VAULT, U128_MAX - 5);
        assertEq(coin.vaultMintAllowance(), U128_MAX - 5, "fixture: allowance near the cap");
        coin.mintForGame_g152734(VAULT, 10);
        assertEq(coin.vaultMintAllowance(), U128_MAX, "mint past the cap saturates");
        coin.mintForGame_g152734(VAULT, U128_MAX);
        assertEq(coin.vaultMintAllowance(), U128_MAX, "a full-width mint onto a full allowance saturates");
        vm.stopPrank();
    }

    function test_transferToVaultSaturates() public {
        vm.startPrank(GAME);
        coin.mintForGame_g152734(alice, 1_000);
        coin.mintForGame_g152734(VAULT, U128_MAX - 5);
        vm.stopPrank();
        uint256 supplyBefore = coin.totalSupply();

        vm.prank(alice);
        coin.transfer(VAULT, 1_000);

        assertEq(coin.vaultMintAllowance(), U128_MAX, "transfer past the cap saturates");
        assertEq(coin.totalSupply(), supplyBefore - 1_000, "the transferred FLIP leaves circulation");
        assertEq(coin.balanceOf(alice), 0, "sender debited");
    }

    function test_belowCapAddsAreExact() public {
        vm.startPrank(GAME);
        coin.mintForGame_g152734(alice, 700);
        coin.mintForGame_g152734(VAULT, 300);
        vm.stopPrank();
        vm.prank(alice);
        coin.transfer(VAULT, 700);
        assertEq(coin.vaultMintAllowance(), 1_000, "exact sum below the cap");
    }
}
