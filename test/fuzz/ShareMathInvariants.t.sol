// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusVaultShare} from "../../contracts/DegenerusVault.sol";

/// @notice Fuzz actual vault previews, payouts, share accounting and refill behavior.
/// @dev Reserves are direct ETH/stETH deposits, without game winnings or afking credits.
contract ShareMathInvariantsTest is DeployProtocol {
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000_000 ether;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    DegenerusVaultShare private share;

    function setUp() public {
        _deployProtocol();
        share = DegenerusVaultShare(vm.computeCreateAddress(address(vault), 2));
        assertEq(share.totalSupply(), INITIAL_SUPPLY);
        share.transfer(ALICE, INITIAL_SUPPLY);
    }

    function testFuzz_partialBurnMatchesPreview(uint96 rawReserve, uint128 rawAmount) public {
        uint256 reserve = bound(rawReserve, 1, 1_000_000 ether);
        uint256 amount = bound(rawAmount, 1, INITIAL_SUPPLY - 1);
        vm.deal(address(vault), reserve);
        uint256 expected = reserve * amount / INITIAL_SUPPLY;
        (uint256 preview, uint256 stPreview) = vault.previewEth(amount);
        assertEq(preview, expected);
        assertEq(stPreview, 0);

        vm.prank(ALICE);
        (uint256 paid, uint256 stPaid) = vault.burnEth(amount);
        assertEq(paid, expected);
        assertEq(stPaid, 0);
        assertEq(ALICE.balance, expected);
        assertEq(address(vault).balance + ALICE.balance, reserve);
        assertEq(share.totalSupply(), INITIAL_SUPPLY - amount);
        assertEq(share.balanceOf(ALICE), INITIAL_SUPPLY - amount);
    }

    function testFuzz_twoHoldersExhaustReserve(uint96 rawReserve, uint128 rawSplit) public {
        uint256 reserve = bound(rawReserve, 1, 1_000_000 ether);
        uint256 aliceShares = bound(rawSplit, 1, INITIAL_SUPPLY - 1);
        uint256 bobShares = INITIAL_SUPPLY - aliceShares;
        vm.deal(address(vault), reserve);
        vm.prank(ALICE);
        share.transfer(BOB, bobShares);
        vm.prank(ALICE);
        vault.burnEth(aliceShares);
        assertEq(ALICE.balance, reserve * aliceShares / INITIAL_SUPPLY);
        vm.prank(BOB);
        vault.burnEth(bobShares);
        assertEq(ALICE.balance + BOB.balance, reserve);
        assertEq(address(vault).balance, 0);
        assertEq(share.balanceOf(ALICE), 0);
        assertEq(share.balanceOf(BOB), INITIAL_SUPPLY);
        assertEq(share.totalSupply(), INITIAL_SUPPLY);
    }

    function testFuzz_refilledSharesRedeemNewDeposits(uint96 firstRaw, uint96 secondRaw) public {
        uint256 first = bound(firstRaw, 1, 1_000_000 ether);
        uint256 second = bound(secondRaw, 1, 1_000_000 ether);
        vm.deal(address(vault), first);
        vm.prank(ALICE);
        vault.burnEth(INITIAL_SUPPLY);
        assertEq(ALICE.balance, first);
        assertEq(share.balanceOf(ALICE), INITIAL_SUPPLY);
        assertEq(share.totalSupply(), INITIAL_SUPPLY);
        vm.deal(address(vault), second);
        vm.prank(ALICE);
        vault.burnEth(INITIAL_SUPPLY);
        assertEq(ALICE.balance, first + second);
        assertEq(address(vault).balance, 0);
        assertEq(share.balanceOf(ALICE), INITIAL_SUPPLY);
        assertEq(share.totalSupply(), INITIAL_SUPPLY);
    }

    function testFuzz_ethPreferredBeforeSteth(uint96 ethRaw, uint96 stRaw, uint128 amountRaw) public {
        uint256 ethReserve = bound(ethRaw, 0, 1_000_000 ether);
        uint256 stReserve = bound(stRaw, 1, 1_000_000 ether);
        uint256 amount = bound(amountRaw, 1, INITIAL_SUPPLY);
        vm.deal(address(vault), ethReserve);
        mockStETH.mint(address(vault), stReserve);
        uint256 claim = (ethReserve + stReserve) * amount / INITIAL_SUPPLY;
        uint256 expectedEth = claim < ethReserve ? claim : ethReserve;
        (uint256 previewEth, uint256 previewSt) = vault.previewEth(amount);
        assertEq(previewEth, expectedEth);
        assertEq(previewSt, claim - expectedEth);
        vm.prank(ALICE);
        (uint256 paidEth, uint256 paidSt) = vault.burnEth(amount);
        assertEq(paidEth, expectedEth);
        assertEq(paidSt, claim - expectedEth);
        assertEq(ALICE.balance, paidEth);
        assertEq(mockStETH.balanceOf(ALICE), paidSt);
        assertEq(address(vault).balance + mockStETH.balanceOf(address(vault)) + claim,
            ethReserve + stReserve);
    }
}
