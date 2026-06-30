// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title EthInEventsTest
/// @notice The ETH-in slices that lack a natural 1:1 event get a dedicated per-product event
///         carrying the spend (EntriesBought / WhalePassPurchased / LazyPassPurchased); the foil
///         premium rides FoilPackBought.weiIn. Each carries weiIn as its LAST data word, disjoint
///         from LootBoxBuy / BetPlaced / DeityPassPurchased so an off-chain ledger sums them for
///         the ETH-in total. Level-0 prices: 1 whole ticket (qty 400) = 0.01 ETH, whale pass =
///         2.4 ETH, lazy pass = 0.24 ETH, foil premium = 10 prices = 0.1 ETH.
contract EthInEventsTest is DeployProtocol {
    bytes32 private constant TICKETS_SIG =
        keccak256("EntriesBought(address,uint256,uint256)");
    bytes32 private constant WHALE_SIG =
        keccak256("WhalePassPurchased(address,uint256,uint256)");
    bytes32 private constant LAZY_SIG =
        keccak256("LazyPassPurchased(address,uint24,uint256)");
    bytes32 private constant FOIL_SIG =
        keccak256("FoilPackBought(address,uint24,uint16,uint256)");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    function test_MintEmitsTicketsBought() public {
        address buyer = makeAddr("ethin_mint");
        vm.deal(buyer, 0.01 ether);
        vm.recordLogs();
        vm.prank(buyer);
        game.purchase{value: 0.01 ether}(
            buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false
        );
        (uint256 qty, uint256 weiIn, bool found) = _evt2(vm.getRecordedLogs(), TICKETS_SIG, buyer);
        assertTrue(found, "mint emits EntriesBought");
        assertEq(qty, 400, "entryQuantityScaled == purchase units");
        assertEq(weiIn, 0.01 ether, "weiIn == ticket cost");
    }

    /// @dev A lootbox-only buy (no tickets) must NOT emit EntriesBought — the box leg rides
    ///      LootBoxBuy, so the `ticketCost != 0` guard keeps them disjoint.
    function test_LootboxOnlyEmitsNoTicketsBought() public {
        address buyer = makeAddr("ethin_boxonly");
        vm.deal(buyer, 0.05 ether);
        vm.recordLogs();
        vm.prank(buyer);
        game.purchase{value: 0.05 ether}(
            buyer, 0, 0.05 ether, bytes32(0), MintPaymentKind.DirectEth, false
        );
        (, , bool found) = _evt2(vm.getRecordedLogs(), TICKETS_SIG, buyer);
        assertFalse(found, "ticketCost==0 -> no EntriesBought");
    }

    function test_WhalePassEmitsWhalePassPurchased() public {
        address buyer = makeAddr("ethin_whale");
        vm.deal(buyer, 2.4 ether);
        vm.recordLogs();
        vm.prank(buyer);
        game.purchaseWhalePass{value: 2.4 ether}(buyer, 1);
        (uint256 quantity, uint256 weiIn, bool found) = _evt2(vm.getRecordedLogs(), WHALE_SIG, buyer);
        assertTrue(found, "whale pass emits WhalePassPurchased");
        assertEq(quantity, 1, "quantity == passes bought");
        assertEq(weiIn, 2.4 ether, "weiIn == totalPrice");
    }

    function test_LazyPassEmitsLazyPassPurchased() public {
        address buyer = makeAddr("ethin_lazy");
        vm.deal(buyer, 0.24 ether);
        vm.recordLogs();
        vm.prank(buyer);
        game.purchaseLazyPass{value: 0.24 ether}(buyer);
        (, uint256 weiIn, bool found) = _evt2(vm.getRecordedLogs(), LAZY_SIG, buyer);
        assertTrue(found, "lazy pass emits LazyPassPurchased");
        assertEq(weiIn, 0.24 ether, "weiIn == totalPrice");
    }

    /// @dev A foil purchase = a mint leg (EntriesBought) + the foil premium (FoilPackBought.weiIn),
    ///      disjoint, summing to the full 0.11 ETH spend.
    function test_FoilMintLegAndPremium() public {
        address buyer = makeAddr("ethin_foil");
        vm.deal(buyer, 1 ether);
        vm.recordLogs();
        vm.prank(buyer);
        game.purchase{value: 1 ether}(
            buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth, true
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (, uint256 mintWei, bool mintFound) = _evt2(logs, TICKETS_SIG, buyer);
        (, uint256 foilWei, bool foilFound) = _evt2(logs, FOIL_SIG, buyer);
        assertTrue(mintFound, "foil purchase emits the mint-leg EntriesBought");
        assertEq(mintWei, 0.01 ether, "mint leg == ticket cost");
        assertTrue(foilFound, "foil purchase emits FoilPackBought");
        assertEq(foilWei, 0.1 ether, "foil premium == 10 ticket prices");
    }

    /// @dev First log matching (sig, player); decodes the two non-indexed data words. Every ETH-in
    ///      event places weiIn as its LAST word, so `weiIn` is the 2nd return regardless of event.
    function _evt2(Vm.Log[] memory logs, bytes32 sig, address player)
        internal
        pure
        returns (uint256 first, uint256 weiIn, bool found)
    {
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].topics.length >= 2 &&
                logs[i].topics[0] == sig &&
                address(uint160(uint256(logs[i].topics[1]))) == player
            ) {
                (first, weiIn) = abi.decode(logs[i].data, (uint256, uint256));
                return (first, weiIn, true);
            }
        }
        return (0, 0, false);
    }
}
