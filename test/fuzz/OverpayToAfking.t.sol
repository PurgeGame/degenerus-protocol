// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenesisFixture} from "./helpers/DegenesisFixture.sol";
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
            id = game.walletIdOf_g3120(a);
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

        // A sub needs a seat (the sole afking credential).
        vm.prank(ContractAddresses.GAME);
        afkingSubToken.mintSeatFor(sub);
        uint32 subId = _aid(sub);

        uint256 funded = 1 ether;
        vm.expectEmit(true, false, false, true, address(game));
        emit AfkingFunded(subId, funded);
        uint256 seat = _seatOf(sub);
        vm.prank(sub);
        game.subscribe{value: funded}(0, true, 1, seat);
        assertEq(game.afkingFundingOf(sub), funded, "the subscriber's own bucket holds it");
    }

    /// @notice An approved operator subscribing for the account credits — and logs — the
    ///         SUBSCRIBER's bucket, never the operator's. This is the misdirection guard.
    function test_SubscribeValueByOperatorCreditsSubscriber() public {
        _finishSubscriptionWindow();
        address sub = makeAddr("subOperatorFunded");
        address operator = makeAddr("subOperator");
        vm.deal(operator, 2 ether);

        vm.prank(ContractAddresses.GAME);
        afkingSubToken.mintSeatFor(sub);
        uint32 subscriberId = _aid(sub);
        uint256 seat = _seatOf(sub);
        vm.prank(sub);
        game.setOperatorApproval(subscriberId, operator, true);

        uint256 funded = 1 ether;
        vm.expectEmit(true, false, false, true, address(game));
        emit AfkingFunded(subscriberId, funded);
        vm.prank(operator);
        game.subscribe{value: funded}(subscriberId, true, 1, seat);

        assertEq(game.afkingFundingOf(sub), funded, "subscriber's bucket credited");
        assertEq(game.afkingFundingOf(operator), 0, "operator's own bucket untouched");
    }
}

/// @notice A Degenesis box bought with more ETH than it costs credits the excess to the payer's afking.
contract OverpayToAfkingDegenesis is DegenesisFixture {
    function setUp() public override {
        super.setUp();
        // Degenesis day 1 is logical day 2: it opens at the first daily request, not with the clock.
        _driveDay(2);
    }

    function test_DegenesisOverpayCreditsAfking() public {
        address buyer = makeAddr("degOver");
        uint256 mintCost = 0.24 ether; // 24 tickets -> earns 0.06 Degenesis credit
        uint256 boxAmount = 0.05 ether;
        uint256 over = 0.02 ether;
        vm.deal(buyer, mintCost + boxAmount + over);

        vm.prank(buyer);
        game.purchase{value: mintCost}(0, 9600, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(game.degenesisCreditOf(buyer), mintCost / 4, "the buy earned a quarter as credit");

        vm.prank(buyer);
        game.buyDegenesisBox{value: boxAmount + over}(0, boxAmount);

        assertEq(game.afkingFundingOf(buyer), over, "Degenesis overpay -> afking");
        assertEq(game.degenesisCreditOf(buyer), mintCost / 4 - boxAmount, "the box consumed its amount in credit");
        assertEq(buyer.balance, 0, "nothing returned/stranded");
    }
}
