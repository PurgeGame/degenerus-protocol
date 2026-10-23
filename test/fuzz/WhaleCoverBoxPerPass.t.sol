// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

/// @title Whale pass boxes: one box per pass bought, folded to at most 100
/// @notice A pass purchase appends its own queue entry of min(passes, 100) equal boxes sharing 10%
///         of the price paid, each floored to whole 0.001 ETH. A lazy pass records one box; the
///         bulk-buy bonus passes never add a box, the count keys on money in. Up to 1,000 paid
///         passes per purchase; tickets, Craps credit and the DGNRS reward follow the paid count.
contract WhaleCoverBoxPerPass is DeployProtocol {
    using BoxOrderLib for uint256;

    uint256 private constant EARLY_PRICE = 2.4 ether;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    /// @dev The entry the purchase just appended: the write buffer's last position.
    function _lastEntry(address who) private view returns (uint256 word) {
        uint48 wb = RecyclingState.writeBuffer(address(game));
        uint256 n = RecyclingState.boxCount(address(game), wb);
        require(n != 0, "no entry appended");
        word = RecyclingState.boxEntry(address(game), wb, n - 1);
        require(word.boId() == game.walletIdOf_g3120(who), "the last entry is the buyer's");
    }

    function _buyWhale(address who, uint256 q) private {
        uint256 price = EARLY_PRICE * q;
        vm.deal(who, who.balance + price);
        uint48 wb = RecyclingState.writeBuffer(address(game));
        uint256 before = RecyclingState.boxCount(address(game), wb);
        vm.prank(who);
        game.purchaseWhalePass{value: price}(0, q, bytes32(0));
        assertEq(RecyclingState.boxCount(address(game), wb), before + 1, "a pass purchase appends one entry");
    }

    /// @dev Expected per-box value: 10% of the price over min(q, 100) boxes, floored to 0.001 ETH.
    function _perBox(uint256 q) private pure returns (uint256) {
        uint256 boxes = q > 100 ? 100 : q;
        return (EARLY_PRICE * q / 10) / boxes / 0.001 ether * 0.001 ether;
    }

    function testOneBoxPerPassBought() public {
        address who = makeAddr("five");
        _buyWhale(who, 5);
        uint256 word = _lastEntry(who);
        assertEq(word.boCount(), 5, "one box per pass bought");
        assertEq(word.boSizeWei(), 0.24 ether, "each box is 10% of one pass");
        assertEq(word.boHighBits(), 0, "entry bits 85..255 are zero");
    }

    /// @notice 100 passes queue 120 passes' entries but only 100 boxes: the bonus is entries.
    function testBonusPassesAddNoBox() public {
        address who = makeAddr("hundred");
        _buyWhale(who, 100);
        uint256 word = _lastEntry(who);
        assertEq(word.boCount(), 100, "boxes follow money in, not bonus passes");
        assertEq(word.boSizeWei(), 0.24 ether, "box size is per paid pass");
    }

    /// @notice 101 passes fold to 100 boxes sharing the same 10%: 24.24 ETH over 100 boxes floors
    ///         to 0.242 ETH each; the 0.04 ETH remainder stays in the pools the price funded.
    function testHundredOnePassesFoldToHundredBoxes() public {
        address who = makeAddr("hundredone");
        _buyWhale(who, 101);
        uint256 word = _lastEntry(who);
        assertEq(word.boCount(), 100, "the box leg folds to 100 boxes");
        assertEq(word.boSizeWei(), 0.242 ether, "the 10% total floors per box");
        (uint256 normal,) = crapsBattle.passCreditsOf(who);
        assertEq(normal, 101, "Craps credit follows the paid quantity");
    }

    /// @notice 1,000 passes: 100 boxes of 2.4 ETH at the early price; Craps credit, freeze and the
    ///         DGNRS per-pass recurrence follow the 1,000 paid passes.
    function testThousandPasses() public {
        address who = makeAddr("thousand");
        uint256 whalePool = sdgnrs.poolBalance(sDGNRS.Pool.Whale);
        uint256 remaining = whalePool;
        for (uint256 i; i < 1000; ++i) remaining -= remaining * 10_000 / 1_000_000;
        uint256 dgnrsBefore = sdgnrs.balanceOf(who);
        _buyWhale(who, 1000);
        uint256 word = _lastEntry(who);
        assertEq(word.boCount(), 100, "100 boxes");
        assertEq(word.boSizeWei(), 2.4 ether, "240 ETH over 100 boxes");
        (uint256 normal,) = crapsBattle.passCreditsOf(who);
        assertEq(normal, 1000, "Craps credit follows the paid quantity");
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Whale), remaining, "DGNRS pool follows the per-pass recurrence");
        assertEq(sdgnrs.balanceOf(who) - dgnrsBefore, whalePool - remaining, "buyer receives the recurrence total");
    }

    function testThousandOnePassesRevert() public {
        address who = makeAddr("toomany");
        vm.deal(who, EARLY_PRICE * 1001);
        vm.prank(who);
        vm.expectRevert();
        game.purchaseWhalePass{value: EARLY_PRICE * 1001}(0, 1001, bytes32(0));
    }

    function testLazyPassRecordsOneBox() public {
        address who = makeAddr("lazy");
        vm.deal(who, 1 ether);
        vm.prank(who);
        game.purchaseLazyPass{value: 0.24 ether}(0, bytes32(0));
        uint256 word = _lastEntry(who);
        assertEq(word.boCount(), 1, "one box for one pass");
        assertEq(word.boSizeWei(), 0.024 ether, "10% of the lazy pass");
    }

    function testFuzzCountFollowsQuantity(uint256 q) public {
        q = bound(q, 1, 1000);
        address who = makeAddr("fuzz");
        _buyWhale(who, q);
        uint256 word = _lastEntry(who);
        assertEq(word.boCount(), q > 100 ? 100 : q, "count = min(passes, 100)");
        assertEq(word.boSizeWei(), _perBox(q), "per-box value = floor(10% / boxes)");
        assertLe(word.boNominal(), EARLY_PRICE * q / 10, "represented never exceeds the funded 10%");
    }
}
