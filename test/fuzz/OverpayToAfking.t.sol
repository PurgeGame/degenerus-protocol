// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title OverpayToAfking
/// @notice Every ETH a buy doesn't need, and any registered caller's bare send, is credited to the payer's
///         withdrawable afking balance instead of reverting, stranding, or funding the pool.
///         Assertions read the real afkingFundingOf getter (slot-free).
contract OverpayToAfking is DeployProtocol {

    mapping(address => uint32) private _aidCache;

    /// @dev Wallet ID of `a`, registering it when it holds none. Call before any `vm.prank`.
    function _aid(address a) internal returns (uint32 id) {
        id = _aidCache[a];
        if (id == 0) {
            id = game.walletIdOf(a);
            if (id == 0) id = _giveWalletId(a);
            _aidCache[a] = id;
        }
    }

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
            0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false
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
        uint32 aid_ = _aid(buyer);
        vm.prank(buyer);
        game.depositAfkingFunding{value: 0.5 ether}(aid_); // mint will draw from here

        uint256 stray = 0.03 ether;
        vm.prank(buyer);
        game.purchase{value: stray}(
            0, 400, 0, bytes32(0), MintPaymentKind.Claimable, false
        );

        // 0.5 deposited, 0.01 spent on the ticket from afking, +0.03 stray credited back.
        assertEq(game.afkingFundingOf(buyer), 0.5 ether - 0.01 ether + stray, "stray -> afking");
    }

    /// @notice Bare ETH send to the contract -> sender afking (was prize-pool donation).
    function test_PlainSendCreditsAfking() public {
        address sender = makeAddr("plainSender");
        uint256 amt = 0.5 ether;
        vm.deal(sender, amt);
        _aid(sender); // Bare funding deposits require an existing account.

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
            0, 9600, 0, bytes32(0), MintPaymentKind.DirectEth, boxAmount
        );

        assertEq(game.afkingFundingOf(buyer), over, "combined overpay -> afking");
        assertEq(buyer.balance, 0, "nothing returned/stranded");
    }

    /// @notice Whale-pass overpay (fixed price) -> payer afking (was a revert).
    function test_PassOverpayCreditsAfking() public {
        address buyer = makeAddr("passOver");
        uint256 price = 2.4 ether; // early whale-pass unit price, quantity 1
        uint256 over = 0.1 ether;
        vm.deal(buyer, price + over);

        vm.prank(buyer);
        game.purchaseWhalePass{value: price + over}(0, 1, bytes32(0));

        assertEq(game.afkingFundingOf(buyer), over, "pass overpay -> afking");
    }

    /// @notice The refactored depositAfkingFunding still credits exactly msg.value.
    function test_DepositAfkingFundingStillWorks() public {
        address buyer = makeAddr("depositor");
        vm.deal(buyer, 1 ether);
        uint32 aid_ = _aid(buyer);
        vm.prank(buyer);
        game.depositAfkingFunding{value: 1 ether}(aid_);
        assertEq(game.afkingFundingOf(buyer), 1 ether, "deposit credited");
    }

    /// @notice Credited overpay is real, withdrawable ETH (not trapped).
    function test_CreditedOverpayIsWithdrawable() public {
        address buyer = makeAddr("withdrawer");
        uint256 amt = 0.3 ether;
        vm.deal(buyer, amt);
        _aid(buyer); // Bare funding deposits require an existing account.

        vm.prank(buyer);
        (bool ok, ) = address(game).call{value: amt}("");
        assertTrue(ok);
        assertEq(game.afkingFundingOf(buyer), amt);

        vm.prank(buyer);
        game.withdrawAfkingFunding(0, amt);

        assertEq(game.afkingFundingOf(buyer), 0, "withdrew all");
        assertEq(buyer.balance, amt, "ETH back in wallet");
    }

    /// @dev Mirror of the Game's ledger-credit log (DegenerusGameStorage).
    event AfkingFunded(uint32 indexed player, uint256 amount);

    /// @notice A funded subscribe routes its msg.value through the emitting credit helper,
    ///         so the afking ledger's credits are observable and not merely its debits.
    ///         Without the log a funded subscribe made from a contract wallet cannot be
    ///         attributed off-chain at all (the top-level tx value is not the sub's).
    function test_SubscribeValueEmitsAfkingFunded() public {
        _finishSubscriptionWindow();
        address sub = makeAddr("subSelfFunded");
        vm.deal(sub, 2 ether);

        // A sub needs a seat (the sole afking credential) and a grounding purchase.
        vm.prank(ContractAddresses.GAME);
        afkingSubToken.mintSeatFor(sub);
        vm.prank(sub);
        game.purchase{value: 0.01 ether}(
            0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false
        );

        uint256 funded = 1 ether;
        vm.expectEmit(true, false, false, true, address(game));
        emit AfkingFunded(_fixtureId(sub), funded);
        uint256 seat = _seatOf(sub);
        vm.prank(sub);
        game.subscribe{value: funded}(0, false, true, 1, 0, seat);
    }

    /// @notice On an operator-funded sub the credit — and the log — name the FUNDER's
    ///         bucket, never the subscriber's. This is the misdirection guard.
    function test_SubscribeValueEmitsAfkingFundedForOperatorFunder() public {
        _finishSubscriptionWindow();
        address sub = makeAddr("subOperatorFunded");
        address funder = makeAddr("subFunder");
        vm.deal(sub, 2 ether);

        vm.prank(ContractAddresses.GAME);
        afkingSubToken.mintSeatFor(sub);
        vm.prank(sub);
        game.purchase{value: 0.01 ether}(
            0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false
        );

        // The funder consents to fund this subscriber.
        uint32 funderId = _aid(funder);
        uint32 subscriberId = _aid(sub);
        uint256 seat = _seatOf(sub);
        vm.prank(funder);
        game.setAfkingFundingApproval(funderId, subscriberId, true);

        uint256 funded = 1 ether;
        vm.expectEmit(true, false, false, true, address(game));
        emit AfkingFunded(_fixtureId(funder), funded);
        vm.prank(sub);
        game.subscribe{value: funded}(0, false, true, 1, funderId, seat);

        assertEq(game.afkingFundingOf(sub), 0, "subscriber's own bucket untouched");
    }
}
