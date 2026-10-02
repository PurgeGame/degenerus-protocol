// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

/// @title CombinedPresaleBoxFunding
/// @notice Proves buyLootboxAndPresaleBox funds the presale-box leg from whatever funding
///         the player brings. The decisive case: with ZERO claimable balance, a single tx
///         mints a ticket AND a presale box, the box covered entirely by leftover fresh ETH.
///         Before the funding-split change the box leg was claimable-only, so this exact call
///         reverted for lack of claimable -- run this file against HEAD to see it fail.
///
///         Assertions are slot-free (event + balances) so they are robust to the storage
///         layout shifts that stale the vm.load harnesses elsewhere in this suite.
contract CombinedPresaleBoxFunding is DeployProtocol {
    function setUp() public {
        _deployProtocol();
        // Stay inside the deploy-idle liveness window.
        vm.warp(block.timestamp + 1 days);
    }

    /// @notice Fresh ETH alone funds both legs: mint a whole ticket + a 0.05 ETH presale box
    ///         with a buyer holding no claimable. The PresaleBoxBuy event fires for the box,
    ///         and every wei of msg.value is consumed.
    function test_FreshEthFundsPresaleBox_NoClaimable() public {
        address buyer = makeAddr("comboBuyer");

        // Mint 24 whole tickets (0.24 ETH at level-0 price). The mint leg accrues 25% =
        // 0.06 ETH presale-box credit, which gates (and exceeds) the 0.05 ETH box -- so the
        // box is authorized purely by this buy, no scaffolding.
        uint256 ticketQty = 9600;       // 24 * 4 * TICKET_SCALE
        uint256 mintCost = 0.24 ether;  // price(level+1 == 1) * 9600 / 400
        uint256 boxAmount = 0.05 ether;
        uint256 total = mintCost + boxAmount;

        vm.deal(buyer, total);          // ONLY fresh ETH, zero claimable

        vm.recordLogs();
        vm.prank(buyer);
        game.buyLootboxAndPresaleBox{value: total}(
            buyer,
            ticketQty,
            0, // lootBoxAmount
            bytes32(0),
            MintPaymentKind.DirectEth,
            boxAmount
        );

        // The box queued for this buyer at the funded amount (order-independent log scan).
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("PresaleBoxBuy(address,uint48,uint256,bool)");
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].topics[0] == sig &&
                address(uint160(uint256(logs[i].topics[1]))) == buyer
            ) {
                (uint256 amount, bool closing) = abi.decode(logs[i].data, (uint256, bool));
                assertEq(amount, boxAmount, "box funded at requested amount");
                assertFalse(closing, "not the closing box");
                found = true;
            }
        }
        assertTrue(found, "PresaleBoxBuy emitted -> box queued from fresh ETH");
        assertEq(buyer.balance, 0, "fresh ETH funded both the mint and the box");
    }

    function test_StandalonePresaleUsesWriteZeroAndRejectsDuplicate() public {
        _standalonePresaleAndDuplicate(0);
    }

    function test_StandalonePresaleUsesWriteOneAndRejectsDuplicate() public {
        _standalonePresaleAndDuplicate(1);
    }

    function _standalonePresaleAndDuplicate(uint48 writeBuffer) private {
        address buyer = makeAddr("standalonePresaleBuyer");
        vm.deal(buyer, 1 ether);
        // A published word belongs only to the opposite read buffer. A new presale
        // purchase remains valid on either physical write parity while that word exists.
        RecyclingState.seedWord(address(game), writeBuffer ^ 1, bytes32(uint256(0xBEEF)));
        vm.prank(buyer);
        game.purchase{value: 0.48 ether}(buyer, 19_200, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(game.presaleBoxCreditOf(buyer), 0.12 ether, "real purchase funds two box attempts");

        vm.recordLogs();
        vm.prank(buyer);
        game.buyPresaleBox{value: 0.05 ether}(buyer, 0.05 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != keccak256("PresaleBoxBuy(address,uint48,uint256,bool)")) continue;
            assertEq(address(uint160(uint256(logs[i].topics[1]))), buyer);
            assertEq(uint256(logs[i].topics[2]), writeBuffer, "purchase records the write buffer");
            (uint256 amount, bool closing) = abi.decode(logs[i].data, (uint256, bool));
            assertEq(amount, 0.05 ether);
            assertFalse(closing);
            found = true;
        }
        assertTrue(found, "standalone presale purchase succeeded");
        assertEq(game.presaleBoxCreditOf(buyer), 0.07 ether);
        assertEq(game.presaleBoxEthRemaining(), 49.95 ether);

        uint256 gameBalance = address(game).balance;
        uint256 buyerBalance = buyer.balance;
        vm.prank(buyer);
        vm.expectRevert(bytes4(keccak256("E()")));
        game.buyPresaleBox{value: 0.05 ether}(buyer, 0.05 ether);
        assertEq(game.presaleBoxCreditOf(buyer), 0.07 ether, "duplicate rolls back the credit debit");
        assertEq(game.presaleBoxEthRemaining(), 49.95 ether, "duplicate sells no additional box");
        assertEq(address(game).balance, gameBalance, "duplicate retains no payment");
        assertEq(buyer.balance, buyerBalance, "duplicate refunds its fresh ETH");
    }
}
