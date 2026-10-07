// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

/// @title Whale pass boxes: one custom box per pass bought
/// @notice A pass purchase appends its own queue entry holding one custom box per pass bought,
///         each worth 10% of one pass (at most 100 passes, so one box per pass always fits). A
///         lazy pass records one box; the bulk-buy bonus passes never add a box, the count keys
///         on money in.
contract WhaleCoverBoxPerPass is DeployProtocol {
    using BoxOrderLib for uint256;

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
        require(word.boId() == game.walletIdOf(who), "the last entry is the buyer's");
    }

    function _buyWhale(address who, uint256 q) private {
        uint256 price = 2.4 ether * q;
        vm.deal(who, who.balance + price);
        uint48 wb = RecyclingState.writeBuffer(address(game));
        uint256 before = RecyclingState.boxCount(address(game), wb);
        vm.prank(who);
        game.purchaseWhalePass{value: price}(0, q, bytes32(0));
        assertEq(RecyclingState.boxCount(address(game), wb), before + 1, "a pass purchase appends one entry");
    }

    function testOneCustomBoxPerPassBought() public {
        address who = makeAddr("five");
        _buyWhale(who, 5);
        uint256 word = _lastEntry(who);
        assertEq(word.boCustomCount(), 5, "one box per pass bought");
        assertEq(word.boSizeWei(), 0.24 ether, "each box is 10% of one pass");
        assertFalse(word.boCover(), "a pass box is a custom box, not a cover");
        assertEq(word.boSmall() + word.boMed() + word.boLarge(), 0, "no preset boxes");
        assertEq(word.boPresaleWei(), 0, "no presale leg");
    }

    /// @notice 100 passes queue 120 passes' entries but only 100 boxes: the bonus is entries.
    function testBonusPassesAddNoBox() public {
        address who = makeAddr("hundred");
        _buyWhale(who, 100);
        uint256 word = _lastEntry(who);
        assertEq(word.boCustomCount(), 100, "boxes follow money in, not bonus passes");
        assertEq(word.boSizeWei(), 0.24 ether, "box size is per paid pass");
    }

    function testLazyPassRecordsOneBox() public {
        address who = makeAddr("lazy");
        vm.deal(who, 1 ether);
        vm.prank(who);
        game.purchaseLazyPass{value: 0.24 ether}(0, bytes32(0));
        uint256 word = _lastEntry(who);
        assertEq(word.boCustomCount(), 1, "one box for one pass");
        assertEq(word.boSizeWei(), 0.024 ether, "10% of the lazy pass");
    }

    function testFuzzCountEqualsQuantity(uint256 q) public {
        q = bound(q, 1, 100);
        address who = makeAddr("fuzz");
        _buyWhale(who, q);
        uint256 word = _lastEntry(who);
        assertEq(word.boCustomCount(), q, "count = passes bought");
        assertEq(word.boSizeWei(), 0.24 ether, "size = 10% of one pass");
    }
}
