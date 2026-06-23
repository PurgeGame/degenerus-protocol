// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title EthInRecordedTest
/// @notice EthInRecorded fires the ETH-in slices no other ETH-bearing event carries — the mint
///         ticket leg, lazy pass, whale bundle, and foil premium — so an off-chain ledger can
///         total ETH-in disjointly from LootBoxBuy / BetPlaced / DeityPassPurchased. Level-0
///         prices: 1 whole ticket (qty 400) = 0.01 ETH, whale bundle = 2.4 ETH, lazy pass = 0.24 ETH.
contract EthInRecordedTest is DeployProtocol {
    bytes32 private constant ETH_IN_SIG =
        keccak256("EthInRecorded(address,uint256,uint8)");

    uint8 private constant K_MINT = 1;
    uint8 private constant K_LAZY = 2;
    uint8 private constant K_WHALE = 3;
    uint8 private constant K_FOIL = 4;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    function test_MintTicketLegEmitsEthIn() public {
        address buyer = makeAddr("ethin_mint");
        vm.deal(buyer, 0.01 ether);
        vm.recordLogs();
        vm.prank(buyer);
        game.purchase{value: 0.01 ether}(
            buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false
        );
        (uint256 amt, bool found) = _firstEthIn(buyer, K_MINT);
        assertTrue(found, "mint ticket leg emits EthInRecorded kind=1");
        assertEq(amt, 0.01 ether, "mint ticket-leg weiAmount == ticket cost");
    }

    /// @dev A lootbox-only buy (no tickets) must NOT emit a mint EthInRecorded — the box leg is
    ///      carried by LootBoxBuy, so the `ticketCost != 0` guard keeps the two events disjoint.
    function test_LootboxOnlyMintEmitsNoTicketEthIn() public {
        address buyer = makeAddr("ethin_boxonly");
        vm.deal(buyer, 0.05 ether);
        vm.recordLogs();
        vm.prank(buyer);
        game.purchase{value: 0.05 ether}(
            buyer, 0, 0.05 ether, bytes32(0), MintPaymentKind.DirectEth, false
        );
        (, bool found) = _firstEthIn(buyer, K_MINT);
        assertFalse(found, "ticketCost==0 -> no mint EthInRecorded");
    }

    function test_WhaleBundleEmitsEthIn() public {
        address buyer = makeAddr("ethin_whale");
        vm.deal(buyer, 2.4 ether);
        vm.recordLogs();
        vm.prank(buyer);
        game.purchaseWhaleBundle{value: 2.4 ether}(buyer, 1);
        (uint256 amt, bool found) = _firstEthIn(buyer, K_WHALE);
        assertTrue(found, "whale bundle emits EthInRecorded kind=3");
        assertEq(amt, 2.4 ether, "whale weiAmount == totalPrice");
    }

    function test_LazyPassEmitsEthIn() public {
        address buyer = makeAddr("ethin_lazy");
        vm.deal(buyer, 0.24 ether);
        vm.recordLogs();
        vm.prank(buyer);
        game.purchaseLazyPass{value: 0.24 ether}(buyer);
        (uint256 amt, bool found) = _firstEthIn(buyer, K_LAZY);
        assertTrue(found, "lazy pass emits EthInRecorded kind=2");
        assertEq(amt, 0.24 ether, "lazy weiAmount == totalPrice");
    }

    /// @dev A foil purchase = a mint leg (ticketCost) + the foil premium; both fire, disjoint.
    function test_FoilEmitsMintLegAndPremium() public {
        address buyer = makeAddr("ethin_foil");
        vm.deal(buyer, 1 ether);
        vm.recordLogs();
        vm.prank(buyer);
        game.purchase{value: 1 ether}(
            buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth, true
        );
        // getRecordedLogs() drains the buffer, so capture once and search the same array.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256 mintAmt, bool mintFound) = _findEthIn(logs, buyer, K_MINT);
        (uint256 foilAmt, bool foilFound) = _findEthIn(logs, buyer, K_FOIL);
        assertTrue(mintFound, "foil purchase emits mint-leg EthInRecorded kind=1");
        assertEq(mintAmt, 0.01 ether, "foil mint-leg == ticket cost");
        assertTrue(foilFound, "foil purchase emits premium EthInRecorded kind=4");
        assertGt(foilAmt, 0, "foil premium weiAmount > 0");
    }

    /// @dev The first EthInRecorded(player, kind) in the recorded logs; returns (amount, found).
    function _firstEthIn(address player, uint8 kind)
        internal
        returns (uint256, bool)
    {
        return _findEthIn(vm.getRecordedLogs(), player, kind);
    }

    /// @dev Search an already-captured log array (getRecordedLogs drains, so callers needing
    ///      more than one lookup must fetch once and pass the array here).
    function _findEthIn(Vm.Log[] memory logs, address player, uint8 kind)
        internal
        pure
        returns (uint256, bool)
    {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length < 2) continue;
            if (logs[i].topics[0] != ETH_IN_SIG) continue;
            if (address(uint160(uint256(logs[i].topics[1]))) != player) continue;
            (uint256 amt, uint8 k) = abi.decode(logs[i].data, (uint256, uint8));
            if (k == kind) return (amt, true);
        }
        return (0, false);
    }
}
