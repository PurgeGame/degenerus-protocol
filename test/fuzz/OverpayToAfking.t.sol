// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title OverpayToAfking
/// @notice Every ETH a buy doesn't need, and any bare send, is credited to the payer's
///         withdrawable afking balance instead of reverting, stranding, or funding the pool.
///         Assertions read the real afkingFundingOf getter (slot-free).
contract OverpayToAfking is DeployProtocol {
    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    /// @notice DirectEth mint overpay -> payer afking (previously silently stranded).
    function test_MintOverpayCreditsAfking() public {
        address buyer = makeAddr("mintOver");
        uint256 cost = 0.01 ether; // 1 whole ticket at level 0
        uint256 over = 0.02 ether;
        vm.deal(buyer, cost + over);

        vm.prank(buyer);
        game.purchase{value: cost + over}(
            buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false
        );

        assertEq(game.afkingFundingOf(buyer), over, "mint overpay -> afking");
        assertEq(buyer.balance, 0, "no ETH left in wallet / none stranded");
    }

    /// @notice Claimable payKind sending stray ETH -> all of it to afking (was a revert).
    function test_ClaimablePayWithValueCreditsAfking() public {
        address buyer = makeAddr("claimStray");
        // Fund the buyer's afking so the mint itself can settle from afking, and send
        // stray msg.value on a Claimable buy: the msg.value is pure overpay -> afking.
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        game.depositAfkingFunding{value: 0.5 ether}(buyer); // mint will draw from here

        uint256 stray = 0.03 ether;
        vm.prank(buyer);
        game.purchase{value: stray}(
            buyer, 400, 0, bytes32(0), MintPaymentKind.Claimable, false
        );

        // 0.5 deposited, 0.01 spent on the ticket from afking, +0.03 stray credited back.
        assertEq(game.afkingFundingOf(buyer), 0.5 ether - 0.01 ether + stray, "stray -> afking");
    }

    /// @notice Bare ETH send to the contract -> sender afking (was prize-pool donation).
    function test_PlainSendCreditsAfking() public {
        address sender = makeAddr("plainSender");
        uint256 amt = 0.5 ether;
        vm.deal(sender, amt);

        vm.prank(sender);
        (bool ok, ) = address(game).call{value: amt}("");

        assertTrue(ok, "plain send accepted");
        assertEq(game.afkingFundingOf(sender), amt, "plain send -> afking");
    }

    /// @notice Combined mint+box overpay (past mint cost + box) -> payer afking.
    function test_CombinedOverpayCreditsAfking() public {
        address buyer = makeAddr("comboOver");
        uint256 mintCost = 0.24 ether; // 24 tickets -> earns 0.06 box credit
        uint256 boxAmount = 0.05 ether;
        uint256 over = 0.02 ether;
        vm.deal(buyer, mintCost + boxAmount + over);

        vm.prank(buyer);
        game.buyLootboxAndPresaleBox{value: mintCost + boxAmount + over}(
            buyer, 9600, 0, bytes32(0), MintPaymentKind.DirectEth, boxAmount
        );

        assertEq(game.afkingFundingOf(buyer), over, "combined overpay -> afking");
        assertEq(buyer.balance, 0, "nothing returned/stranded");
    }

    /// @notice Whale-bundle overpay (fixed price) -> payer afking (was a revert).
    function test_PassOverpayCreditsAfking() public {
        address buyer = makeAddr("passOver");
        uint256 price = 2.4 ether; // early whale-bundle unit price, quantity 1
        uint256 over = 0.1 ether;
        vm.deal(buyer, price + over);

        vm.prank(buyer);
        game.purchaseWhaleBundle{value: price + over}(buyer, 1);

        assertEq(game.afkingFundingOf(buyer), over, "pass overpay -> afking");
    }

    /// @notice The refactored depositAfkingFunding still credits exactly msg.value.
    function test_DepositAfkingFundingStillWorks() public {
        address buyer = makeAddr("depositor");
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        game.depositAfkingFunding{value: 1 ether}(buyer);
        assertEq(game.afkingFundingOf(buyer), 1 ether, "deposit credited");
    }

    /// @notice Credited overpay is real, withdrawable ETH (not trapped).
    function test_CreditedOverpayIsWithdrawable() public {
        address buyer = makeAddr("withdrawer");
        uint256 amt = 0.3 ether;
        vm.deal(buyer, amt);

        vm.prank(buyer);
        (bool ok, ) = address(game).call{value: amt}("");
        assertTrue(ok);
        assertEq(game.afkingFundingOf(buyer), amt);

        vm.prank(buyer);
        game.withdrawAfkingFunding(amt);

        assertEq(game.afkingFundingOf(buyer), 0, "withdrew all");
        assertEq(buyer.balance, amt, "ETH back in wallet");
    }
}
