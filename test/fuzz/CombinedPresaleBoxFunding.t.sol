// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @title CombinedPresaleBoxFunding
/// @notice Proves buyLootboxAndPresaleBox funds the presale-box leg from whatever funding
///         the player brings. The decisive case: with ZERO claimable balance, a single tx
///         mints a ticket AND a presale box, the box covered entirely by leftover fresh ETH.
///         Before the funding-split change the box leg was claimable-only, so this exact call
///         reverted for lack of claimable -- run this file against HEAD to see it fail.
///
///         Assertions read the purchase event and the entry it names, plus balances.
contract CombinedPresaleBoxFunding is DeployProtocol {
    using BoxOrderLib for uint256;

    bytes32 constant PRESALE_BUY = keccak256("PresaleBoxBuy(address,uint48,uint32,uint256,bool)");

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
            0, // no ordinary box leg: a presale-only entry
            bytes32(0),
            MintPaymentKind.DirectEth,
            boxAmount
        );

        // The box queued for this buyer at the funded amount (order-independent log scan).
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].topics[0] == PRESALE_BUY &&
                address(uint160(uint256(logs[i].topics[1]))) == buyer
            ) {
                (uint32 position, uint256 amount, bool closing) = abi.decode(logs[i].data, (uint32, uint256, bool));
                assertEq(amount, boxAmount, "box funded at requested amount");
                assertFalse(closing, "not the closing box");
                uint256 entry = RecyclingState.boxEntry(address(game), uint48(uint256(logs[i].topics[2])), position);
                assertEq(entry.boId(), game.walletIdOf(buyer), "the named entry is the buyer's");
                assertEq(entry.boPresaleWei(), boxAmount, "the entry holds the applied presale wei");
                assertEq(entry.boCount(), 0, "no ordinary boxes: a presale-only entry");
                found = true;
            }
        }
        assertTrue(found, "PresaleBoxBuy emitted -> box queued from fresh ETH");
        assertEq(buyer.balance, 0, "fresh ETH funded both the mint and the box");
    }

    function test_StandalonePresaleUsesWriteZeroAndRepeatsAsOwnEntry() public {
        _standalonePresaleAndRepeat(0);
    }

    function test_StandalonePresaleUsesWriteOneAndRepeatsAsOwnEntry() public {
        _standalonePresaleAndRepeat(1);
    }

    /// @dev One standalone presale buy, asserting its event names the write buffer and the
    ///      entry it appended; returns that position.
    function _buyAndCheck(address buyer, uint48 writeBuffer, uint256 amount) private returns (uint256 position) {
        uint256 expectedPosition = RecyclingState.boxCount(address(game), writeBuffer);
        vm.recordLogs();
        vm.prank(buyer);
        game.buyPresaleBox{value: amount}(buyer, amount);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != PRESALE_BUY) continue;
            assertEq(address(uint160(uint256(logs[i].topics[1]))), buyer);
            assertEq(uint256(logs[i].topics[2]), writeBuffer, "purchase records the write buffer");
            uint32 pos;
            uint256 applied;
            bool closing;
            (pos, applied, closing) = abi.decode(logs[i].data, (uint32, uint256, bool));
            assertEq(pos, expectedPosition, "the entry joins at the buffer's write count");
            assertEq(applied, amount);
            assertFalse(closing);
            position = pos;
            found = true;
        }
        assertTrue(found, "standalone presale purchase succeeded");
        assertEq(RecyclingState.boxCount(address(game), writeBuffer), expectedPosition + 1, "one entry appended");
        uint256 entry = RecyclingState.boxEntry(address(game), writeBuffer, position);
        assertEq(entry.boId(), game.walletIdOf(buyer));
        assertEq(entry.boPresaleWei(), amount);
    }

    function _standalonePresaleAndRepeat(uint48 writeBuffer) private {
        address buyer = makeAddr("standalonePresaleBuyer");
        vm.deal(buyer, 1 ether);
        // A published word belongs only to the opposite read buffer. A new presale
        // purchase remains valid on either physical write parity while that word exists.
        RecyclingState.seedWord(address(game), writeBuffer ^ 1, bytes32(uint256(0xBEEF)));
        vm.prank(buyer);
        game.purchase{value: 0.48 ether}(buyer, 19_200, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(game.presaleBoxCreditOf(buyer), 0.12 ether, "real purchase funds two box attempts");

        uint256 first = _buyAndCheck(buyer, writeBuffer, 0.05 ether);
        uint256 firstEntry = RecyclingState.boxEntry(address(game), writeBuffer, first);
        assertEq(game.presaleBoxCreditOf(buyer), 0.07 ether);
        assertEq(game.presaleBoxEthRemaining(), 49.95 ether);

        // A repeat purchase by the same wallet in the same buffer is its own entry; the credit
        // gate still applies to it.
        uint256 second = _buyAndCheck(buyer, writeBuffer, 0.05 ether);
        assertEq(second, first + 1, "the repeat purchase is the next entry");
        assertEq(RecyclingState.boxEntry(address(game), writeBuffer, first), firstEntry, "the first entry is untouched");
        assertEq(game.presaleBoxCreditOf(buyer), 0.02 ether, "each purchase consumes its own credit");
        assertEq(game.presaleBoxEthRemaining(), 49.9 ether, "each purchase sells its own box");

        // A third attempt exceeds the remaining credit: it reverts and keeps nothing.
        uint256 count = RecyclingState.boxCount(address(game), writeBuffer);
        uint256 gameBalance = address(game).balance;
        uint256 buyerBalance = buyer.balance;
        vm.prank(buyer);
        vm.expectRevert(bytes4(keccak256("E()")));
        game.buyPresaleBox{value: 0.05 ether}(buyer, 0.05 ether);
        assertEq(game.presaleBoxCreditOf(buyer), 0.02 ether, "the failed buy rolls back the credit debit");
        assertEq(game.presaleBoxEthRemaining(), 49.9 ether, "the failed buy sells no box");
        assertEq(RecyclingState.boxCount(address(game), writeBuffer), count, "the failed buy appends nothing");
        assertEq(address(game).balance, gameBalance, "the failed buy retains no payment");
        assertEq(buyer.balance, buyerBalance, "the failed buy refunds its fresh ETH");
    }
}
