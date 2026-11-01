// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {stdError} from "forge-std/StdError.sol";

/// @title FlipSupplyCeiling
/// @notice FLIP payouts and the craps comp lane are credited inside the mining chain, so they stop
///         at the uint128 supply ceiling instead of reverting. The Vault's own mint stays checked,
///         keeping wallet balances summed to totalSupply for the burns the chain relies on.
contract FlipSupplyCeiling is DeployProtocol {
    uint256 internal constant U128_MAX = type(uint128).max;
    address internal constant GAME = ContractAddresses.GAME;
    address internal constant VAULT = ContractAddresses.VAULT;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        _deployProtocol();
    }

    function _fillTo(uint256 headroomLeft) internal {
        uint256 amount = U128_MAX - coin.totalSupply() - headroomLeft;
        vm.prank(GAME);
        coin.mintForGame_g152734(alice, amount);
        assertEq(coin.totalSupply(), U128_MAX - headroomLeft, "fixture: supply near the ceiling");
    }

    function test_walletMintStopsAtTheSupplyCeiling() public {
        _fillTo(5);
        vm.startPrank(GAME);
        coin.mintForGame_g152734(bob, 10);
        assertEq(coin.balanceOf(bob), 5, "only the headroom is minted");
        assertEq(coin.totalSupply(), U128_MAX, "supply sits at the ceiling");
        coin.mintForGame_g152734(bob, 1);
        coin.mintForGame_g152734(bob, type(uint256).max);
        vm.stopPrank();
        assertEq(coin.balanceOf(bob), 5, "a mint at the ceiling creates nothing and does not revert");
        assertEq(coin.totalSupply(), U128_MAX, "supply unchanged");
    }

    function test_burnAfterSaturatedMintsStaysConsistent() public {
        _fillTo(5);
        vm.startPrank(GAME);
        coin.mintForGame_g152734(bob, 10);
        coin.burnCoin_g27673(bob, 5);
        vm.stopPrank();
        assertEq(coin.balanceOf(bob), 0, "bob burned what he holds");
        assertEq(coin.totalSupply(), U128_MAX - 5, "supply tracks the balances");
    }

    function test_fullWidthVaultMintSaturates() public {
        vm.prank(GAME);
        coin.mintForGame_g152734(VAULT, type(uint256).max);
        assertEq(coin.vaultMintAllowance(), U128_MAX, "a full-width mint to the Vault saturates");
    }

    function test_vaultMintToCannotPassTheCeiling() public {
        _fillTo(5);
        vm.prank(GAME);
        coin.mintForGame_g152734(VAULT, 10);
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(VAULT);
        coin.vaultMintTo(bob, 10);
        vm.prank(VAULT);
        coin.vaultMintTo(bob, 5);
        assertEq(coin.totalSupply(), U128_MAX, "the Vault fills the headroom exactly");
        assertEq(coin.vaultMintAllowance(), 5, "only the minted part leaves the allowance");
    }

    function test_crapsCompLaneSaturates() public {
        uint256 before = coin.crapsCompAllowance();
        vm.startPrank(ContractAddresses.CRAPS);
        coin.creditCrapsComps_g37225(U128_MAX - before - 1);
        coin.creditCrapsComps_g37225(10);
        coin.creditCrapsComps_g37225(U128_MAX);
        vm.stopPrank();
        assertEq(coin.crapsCompAllowance(), U128_MAX, "the comp lane saturates instead of reverting");
    }
}
