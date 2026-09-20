// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusVault} from "../../contracts/DegenerusVault.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {FLIP} from "../../contracts/FLIP.sol";

/// @dev Real vault -> table -> FLIP coverage: pool funding spends shared comp budget and a
///      delegate's limit atomically, never wallet backing or a vault mint allowance.
contract CrapsCompDonationTest is DeployProtocol {
    address private player = makeAddr("comp_donation_player");
    address private delegate = makeAddr("comp_donation_delegate");
    address private stranger = makeAddr("comp_donation_stranger");
    uint64 private slot;
    uint256 private index;
    bytes32 private key;

    event CrapsCompDonated(address indexed operator, bool indexed custom, uint256 indexed index, uint256 charged);

    function setUp() public {
        _deployProtocol();
        vm.prank(ContractAddresses.CREATOR);
        slot = crapsBattle.createBattle(300, 4, 5, 2, 0, uint40(block.timestamp + 1 hours), false, 0);
        index = slot - crapsBattle.CUSTOM_SLOT_BASE();
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(player, 2_000 ether);
        vm.prank(player);
        uint256 betId = crapsBattle.enterBattle(slot, uint32(0), 1);
        key = crapsBattle.battleKeyOf(betId);
    }

    function test_ownerFundsPoolFromCompBudgetWithoutBurningAssets() public {
        uint256 lane = coin.crapsCompAllowance();
        uint256 supply = coin.totalSupply();
        uint256 vaultBacking = coin.vaultMintAllowance();
        uint256 playerBalance = coin.balanceOf(player);
        uint256 ownerBalance = coin.balanceOf(ContractAddresses.CREATOR);
        vm.prank(ContractAddresses.CREATOR);
        vault.setCrapsCompAllowance(ContractAddresses.CREATOR, 1 ether);

        vm.prank(ContractAddresses.CREATOR);
        vm.expectEmit(true, true, true, true, address(vault));
        emit CrapsCompDonated(ContractAddresses.CREATOR, true, index, 1_000 ether);
        uint256 charged = vault.crapsCompDonate(true, index, 10);

        assertEq(charged, 1_000 ether);
        assertEq(crapsBattle.battleOf(key).seed, charged);
        assertEq(coin.crapsCompAllowance(), lane - charged);
        assertEq(coin.totalSupply(), supply);
        assertEq(coin.vaultMintAllowance(), vaultBacking);
        assertEq(coin.balanceOf(player), playerBalance);
        assertEq(coin.balanceOf(ContractAddresses.CREATOR), ownerBalance);
        assertEq(vault.crapsCompAllowanceOf(ContractAddresses.CREATOR), 1 ether, "owner used delegate allowance");
    }

    function test_delegateSharesOneLimitAcrossPassGrantsAndDonations() public {
        uint256 lane = coin.crapsCompAllowance();
        vm.prank(ContractAddresses.CREATOR);
        vault.setCrapsCompAllowance(delegate, 23_800 ether);
        uint256[] memory codes = new uint256[](1);
        // Bank one normal day pass for the player: 22,800 FLIP.
        codes[0] = uint256(uint160(player)) | (uint256(4) << 160) | (uint256(1) << 200);
        vm.prank(delegate);
        vault.crapsComp(codes);
        assertEq(vault.crapsCompAllowanceOf(delegate), 1_000 ether);

        vm.prank(delegate);
        vm.expectRevert(DegenerusVault.Insufficient.selector);
        vault.crapsCompDonate(true, index, 11);
        assertEq(crapsBattle.battleOf(key).seed, 0, "failed donation left a seed");
        assertEq(coin.crapsCompAllowance(), lane - 22_800 ether, "failed donation spent comp budget");
        assertEq(vault.crapsCompAllowanceOf(delegate), 1_000 ether);

        vm.prank(delegate);
        vault.crapsCompDonate(true, index, 10);
        assertEq(crapsBattle.battleOf(key).seed, 1_000 ether);
        assertEq(coin.crapsCompAllowance(), lane - 23_800 ether);
        assertEq(vault.crapsCompAllowanceOf(delegate), 0);
        vm.prank(delegate);
        vm.expectRevert(DegenerusVault.NotVaultOwner.selector);
        vault.crapsCompDonate(true, index, 1);
    }

    function test_unapprovedAndRevokedCallersCannotSpendCompBudget() public {
        uint256 lane = coin.crapsCompAllowance();
        vm.prank(stranger);
        vm.expectRevert(DegenerusVault.NotVaultOwner.selector);
        vault.crapsCompDonate(true, index, 1);
        vm.startPrank(ContractAddresses.CREATOR);
        vault.setCrapsCompAllowance(delegate, 1_000 ether);
        vault.setCrapsCompAllowance(delegate, 0);
        vm.stopPrank();
        vm.prank(delegate);
        vm.expectRevert(DegenerusVault.NotVaultOwner.selector);
        vault.crapsCompDonate(true, index, 1);
        assertEq(coin.crapsCompAllowance(), lane);
        assertEq(crapsBattle.battleOf(key).seed, 0);
    }

    function test_insufficientSharedBudgetRollsBackDelegateAllowanceAndSeed() public {
        uint256 lane = coin.crapsCompAllowance();
        vm.prank(ContractAddresses.CREATOR);
        vault.setCrapsCompAllowance(delegate, lane + 100 ether);
        vm.prank(delegate);
        vm.expectRevert(FLIP.Insufficient.selector);
        vault.crapsCompDonate(true, index, uint24(lane / 100 ether + 1));
        assertEq(vault.crapsCompAllowanceOf(delegate), lane + 100 ether);
        assertEq(coin.crapsCompAllowance(), lane);
        assertEq(crapsBattle.battleOf(key).seed, 0);
    }

    function test_aClosedPoolCannotReceiveCompFunds() public {
        uint256 lane = coin.crapsCompAllowance();
        vm.prank(ContractAddresses.CREATOR);
        vault.setCrapsCompAllowance(delegate, 1_000 ether);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(delegate);
        vm.expectRevert(CrapsBattle.BonusPeriodSpent.selector);
        vault.crapsCompDonate(true, index, 10);
        assertEq(vault.crapsCompAllowanceOf(delegate), 1_000 ether);
        assertEq(coin.crapsCompAllowance(), lane);
        assertEq(crapsBattle.battleOf(key).seed, 0);
    }

    function test_directDonationCannotChargeCompBudget() public {
        uint256 lane = coin.crapsCompAllowance();
        uint256 playerBalance = coin.balanceOf(player);
        vm.prank(player);
        crapsBattle.donate(true, index, 1);
        assertEq(coin.crapsCompAllowance(), lane);
        assertEq(coin.balanceOf(player), playerBalance - 100 ether);
        assertEq(crapsBattle.battleOf(key).seed, 100 ether);
    }
}
