// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title WwxrpVaultEscrowTest -- WWXRP vault escrow routing (FLIP model).
///
/// @notice The vault holds no circulating WWXRP. Transfers targeting it
///         de-circulate into vaultAllowance (totalSupply down, allowance up);
///         mints targeting it escrow straight to allowance (supply untouched).
///         supplyIncUncirculated is conserved across both.
contract WwxrpVaultEscrowTest is DeployProtocol {
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event VaultEscrowRecorded(address indexed sender, uint256 amount);
    event VaultAllowanceSpent(address indexed spender, uint256 amount);

    error InsufficientVaultAllowance();

    address private constant VAULT = ContractAddresses.VAULT;

    address private alice;

    function setUp() public {
        _deployProtocol();
        alice = makeAddr("escrow_alice");
        // Seed alice with circulating WWXRP through the real prize channel.
        vm.prank(address(coinflip));
        wwxrp.mintPrize(alice, 1000 ether);
    }

    function testTransferToVaultEscrows() public {
        uint256 allowanceBefore = wwxrp.vaultAllowance();
        uint256 supplyBefore = wwxrp.totalSupply();
        uint256 supplyIncBefore = wwxrp.supplyIncUncirculated();

        vm.expectEmit(true, true, false, true, address(wwxrp));
        emit Transfer(alice, address(0), 400 ether);
        vm.expectEmit(true, false, false, true, address(wwxrp));
        emit VaultEscrowRecorded(alice, 400 ether);
        vm.prank(alice);
        wwxrp.transfer(VAULT, 400 ether);

        assertEq(wwxrp.balanceOf(alice), 600 ether, "sender debited");
        assertEq(wwxrp.balanceOf(VAULT), 0, "vault holds no circulating WWXRP");
        assertEq(wwxrp.totalSupply(), supplyBefore - 400 ether, "de-circulated");
        assertEq(wwxrp.vaultAllowance(), allowanceBefore + 400 ether, "allowance credited");
        assertEq(wwxrp.supplyIncUncirculated(), supplyIncBefore, "conserved across escrow");
    }

    function testTransferFromToVaultEscrows() public {
        address spender = makeAddr("escrow_spender");
        vm.prank(alice);
        wwxrp.approve(spender, 250 ether);

        uint256 allowanceBefore = wwxrp.vaultAllowance();
        uint256 supplyBefore = wwxrp.totalSupply();

        vm.prank(spender);
        wwxrp.transferFrom(alice, VAULT, 250 ether);

        assertEq(wwxrp.balanceOf(alice), 750 ether, "owner debited");
        assertEq(wwxrp.balanceOf(VAULT), 0, "vault holds no circulating WWXRP");
        assertEq(wwxrp.totalSupply(), supplyBefore - 250 ether, "de-circulated");
        assertEq(wwxrp.vaultAllowance(), allowanceBefore + 250 ether, "allowance credited");
        assertEq(wwxrp.allowance(alice, spender), 0, "spender allowance spent");
    }

    function testMintPrizeToVaultEscrows() public {
        uint256 allowanceBefore = wwxrp.vaultAllowance();
        uint256 supplyBefore = wwxrp.totalSupply();

        // The live path: coinflip loss rewards can target the vault (it flips daily).
        vm.expectEmit(true, false, false, true, address(wwxrp));
        emit VaultEscrowRecorded(address(0), 7 ether);
        vm.prank(address(coinflip));
        wwxrp.mintPrize(VAULT, 7 ether);

        assertEq(wwxrp.balanceOf(VAULT), 0, "vault holds no circulating WWXRP");
        assertEq(wwxrp.totalSupply(), supplyBefore, "supply untouched by escrowed mint");
        assertEq(wwxrp.vaultAllowance(), allowanceBefore + 7 ether, "allowance credited");
    }

    function testVaultMintToSelfIsNetNeutral() public {
        uint256 allowanceBefore = wwxrp.vaultAllowance();
        uint256 supplyBefore = wwxrp.totalSupply();

        // Spend-from-allowance then escrow-back: coherent no-op, never a balance.
        vm.prank(VAULT);
        wwxrp.vaultMintTo(VAULT, 5 ether);

        assertEq(wwxrp.vaultAllowance(), allowanceBefore, "allowance round-trips");
        assertEq(wwxrp.totalSupply(), supplyBefore, "supply untouched");
        assertEq(wwxrp.balanceOf(VAULT), 0, "vault holds no circulating WWXRP");
    }

    function testVaultBurnSpendsAllowance() public {
        uint256 allowanceBefore = wwxrp.vaultAllowance();
        uint256 supplyBefore = wwxrp.totalSupply();

        // The live path: game burns the vault's WWXRP Degenerette bet
        // (gameDegeneretteBet passthrough -> placeDegeneretteBet -> burnForGame).
        vm.expectEmit(true, false, false, true, address(wwxrp));
        emit VaultAllowanceSpent(VAULT, 30 ether);
        vm.prank(address(game));
        wwxrp.burnForGame(VAULT, 30 ether);

        assertEq(wwxrp.vaultAllowance(), allowanceBefore - 30 ether, "allowance spent");
        assertEq(wwxrp.totalSupply(), supplyBefore, "supply untouched by vault burn");
        assertEq(wwxrp.balanceOf(VAULT), 0, "vault holds no circulating WWXRP");
    }

    function testVaultBurnBeyondAllowanceReverts() public {
        uint256 allowanceNow = wwxrp.vaultAllowance();
        vm.prank(address(game));
        vm.expectRevert(InsufficientVaultAllowance.selector);
        wwxrp.burnForGame(VAULT, allowanceNow + 1);
    }

    function testNonVaultFlowsUnchanged() public {
        address bob = makeAddr("escrow_bob");
        uint256 supplyBefore = wwxrp.totalSupply();

        vm.prank(alice);
        wwxrp.transfer(bob, 100 ether);
        assertEq(wwxrp.balanceOf(bob), 100 ether, "plain transfer credits");
        assertEq(wwxrp.totalSupply(), supplyBefore, "plain transfer keeps supply");

        vm.prank(VAULT);
        wwxrp.vaultMintTo(bob, 10 ether);
        assertEq(wwxrp.balanceOf(bob), 110 ether, "vault mint to player circulates");
        assertEq(wwxrp.totalSupply(), supplyBefore + 10 ether, "circulating mint grows supply");
    }
}
