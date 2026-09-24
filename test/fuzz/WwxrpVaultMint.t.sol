// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {WWXRP} from "../../contracts/WWXRP.sol";
import {DegenerusVaultShare} from "../../contracts/DegenerusVault.sol";

/// @notice Uncapped owner minting and ordinary ERC20 accounting for vault-held WWXRP.
contract WwxrpVaultMintTest is DeployProtocol {
    event Transfer(address indexed from, address indexed to, uint256 amount);
    address private constant VAULT = ContractAddresses.VAULT;
    address private owner;
    address private alice;

    function setUp() public {
        _deployProtocol();
        owner = ContractAddresses.CREATOR;
        alice = makeAddr("wwxrp_alice");
        assertTrue(vault.isVaultOwner(owner));
        vm.prank(address(coinflip));
        wwxrp.mintPrize(alice, 1000 ether);
    }

    function testOwnerCanMintBeyondTheFormerReserveRepeatedly() public {
        uint256 amount = 10_000_000_000 ether;
        uint256 supply = wwxrp.totalSupply();
        vm.prank(owner);
        wwxrp.vaultMintTo(alice, amount);
        vm.prank(owner);
        vault.wwxrpMint(alice, amount);
        assertEq(wwxrp.balanceOf(alice), 1000 ether + 2 * amount);
        assertEq(wwxrp.totalSupply(), supply + 2 * amount);
    }

    function testFuzzOwnerMintHasNoAllocationLimit(uint128 amount) public {
        uint256 supply = wwxrp.totalSupply();
        vm.prank(owner);
        wwxrp.vaultMintTo(alice, amount);
        assertEq(wwxrp.totalSupply(), supply + amount);
        assertEq(wwxrp.balanceOf(alice), 1000 ether + uint256(amount));
    }

    function testStrangerCannotMintEvenZero() public {
        vm.prank(alice);
        vm.expectRevert(WWXRP.NotVaultOwner.selector);
        wwxrp.vaultMintTo(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(WWXRP.NotVaultOwner.selector);
        wwxrp.vaultMintTo(alice, 0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("NotVaultOwner()"));
        vault.wwxrpMint(alice, 1 ether);
    }

    function testMintAuthorityFollowsCurrentDgveOwnership() public {
        DegenerusVaultShare dgve = DegenerusVaultShare(computeCreateAddress(VAULT, 2));
        uint256 shares = dgve.balanceOf(owner);
        vm.prank(owner);
        dgve.transfer(alice, shares);
        assertFalse(vault.isVaultOwner(owner));
        assertTrue(vault.isVaultOwner(alice));
        vm.prank(owner);
        vm.expectRevert(WWXRP.NotVaultOwner.selector);
        wwxrp.vaultMintTo(owner, 1 ether);
        vm.prank(alice);
        wwxrp.vaultMintTo(alice, 2 ether);
        assertEq(wwxrp.balanceOf(alice), 1002 ether);
    }

    function testMintToZeroMintsNothing() public {
        uint256 supply = wwxrp.totalSupply();
        vm.prank(owner);
        wwxrp.vaultMintTo(address(0), 1 ether);
        assertEq(wwxrp.totalSupply(), supply, "a zero recipient mints nothing");
        assertEq(wwxrp.balanceOf(address(0)), 0, "and credits nobody");
    }

    function testTransferToVaultUsesOrdinaryBalance() public {
        uint256 supply = wwxrp.totalSupply();
        vm.expectEmit(true, true, false, true, address(wwxrp));
        emit Transfer(alice, VAULT, 400 ether);
        vm.prank(alice);
        wwxrp.transfer(VAULT, 400 ether);
        assertEq(wwxrp.balanceOf(alice), 600 ether);
        assertEq(wwxrp.balanceOf(VAULT), 400 ether);
        assertEq(wwxrp.totalSupply(), supply);
    }

    function testTransferFromToVaultStillSpendsErc20Approval() public {
        address spender = makeAddr("spender");
        vm.prank(alice);
        wwxrp.approve(spender, 250 ether);
        uint256 supply = wwxrp.totalSupply();
        vm.prank(spender);
        wwxrp.transferFrom(alice, VAULT, 250 ether);
        assertEq(wwxrp.balanceOf(VAULT), 250 ether);
        assertEq(wwxrp.balanceOf(alice), 750 ether);
        assertEq(wwxrp.allowance(alice, spender), 0);
        assertEq(wwxrp.totalSupply(), supply);
    }

    function testPrizeMintToVaultCirculates() public {
        uint256 supply = wwxrp.totalSupply();
        vm.prank(address(coinflip));
        wwxrp.mintPrize(VAULT, 7 ether);
        assertEq(wwxrp.balanceOf(VAULT), 7 ether);
        assertEq(wwxrp.totalSupply(), supply + 7 ether);
    }

    function testVaultCanMintToItselfAndBurnItsBalance() public {
        uint256 supply = wwxrp.totalSupply();
        vm.prank(owner);
        vault.wwxrpMint(VAULT, 50 ether);
        assertEq(wwxrp.balanceOf(VAULT), 50 ether);
        vm.prank(address(game));
        wwxrp.burnForGame(VAULT, 30 ether);
        assertEq(wwxrp.balanceOf(VAULT), 20 ether);
        assertEq(wwxrp.totalSupply(), supply + 20 ether);
    }

    function testVaultBurnRequiresRealBalance() public {
        vm.prank(address(game));
        vm.expectRevert(WWXRP.InsufficientBalance.selector);
        wwxrp.burnForGame(VAULT, 1 ether);
    }
}
