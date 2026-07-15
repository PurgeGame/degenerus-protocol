// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

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
}
