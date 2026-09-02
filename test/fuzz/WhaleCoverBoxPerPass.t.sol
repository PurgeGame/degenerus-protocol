// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {C1Viewer} from "../repro/C1BoxAutoOpen.t.sol";

/// @title Whale pass boxes: one custom box per pass bought
/// @notice A whale purchase records its 10% lootbox spend in the custom lane as one box per
///         pass bought while the entry has room under the 100-box cap, fewer and larger boxes
///         as the cap closes, and none at a full entry, whose held customs absorb the value at
///         the value-weighted average size. No entry ever holds more than 100 boxes; the one
///         refusal is a full entry with no custom to fold into.
///         A lazy pass records one box; purchases in the same index add their counts; the
///         bulk-buy bonus passes never add a box, the count keys on money in.
contract WhaleCoverBoxPerPass is DeployProtocol {
    uint256 private constant LOOTBOX_ORDER_SLOT = 15;
    uint256 private constant LB_COVER_SHIFT = 161;
    uint256 private constant LB_COVER_MASK = 0xFFFFFFFFFFFF;
    uint256 private constant LB_CUSTOM_COUNT_SHIFT = 105;
    uint256 private constant LB_CUSTOM_SIZE_SHIFT = 113;
    uint256 private constant LB_CUSTOM_SIZE_MASK = 0xFFFFFFFFFFFF;
    uint256 private constant LB_CUSTOM_SCALE = 1e12;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    function _idx() private returns (uint48 v) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(C1Viewer).runtimeCode);
        v = C1Viewer(payable(address(game))).lrIndexView();
        vm.etch(address(game), real);
    }

    function _order(address who) private returns (uint256) {
        bytes32 first = keccak256(abi.encode(uint256(_idx()), LOOTBOX_ORDER_SLOT));
        bytes32 second = keccak256(abi.encode(uint256(uint160(who)), uint256(first)));
        return uint256(vm.load(address(game), second));
    }

    function _coverWei(uint256 word) private pure returns (uint256) {
        return ((word >> LB_COVER_SHIFT) & LB_COVER_MASK) * LB_CUSTOM_SCALE;
    }

    function _customCount(uint256 word) private pure returns (uint256) {
        return (word >> LB_CUSTOM_COUNT_SHIFT) & 0xFF;
    }

    /// @dev The lane stores wei / 1e12, so an average truncates at that unit.
    function _avg(uint256 totalWei, uint256 n) private pure returns (uint256) {
        return ((totalWei / LB_CUSTOM_SCALE) / n) * LB_CUSTOM_SCALE;
    }

    function _customSize(uint256 word) private pure returns (uint256) {
        return ((word >> LB_CUSTOM_SIZE_SHIFT) & LB_CUSTOM_SIZE_MASK) * LB_CUSTOM_SCALE;
    }

    function _buyWhale(address who, uint256 q) private {
        uint256 price = 2.4 ether * q;
        vm.deal(who, who.balance + price);
        vm.prank(who);
        game.purchaseWhalePass{value: price}(who, q, bytes32(0));
    }

    function _buyCustoms(address who, uint256 n) private {
        uint256 cost = 1 ether + 0.01 ether * n;
        vm.deal(who, who.balance + cost);
        vm.prank(who);
        game.purchase{value: cost}(who, 400, BoxOrderLib.boOrder(0, 0, 0, n, 0.01 ether), bytes32(0), MintPaymentKind.DirectEth, false);
    }

    function testOneCustomBoxPerPassBought() public {
        address who = makeAddr("five");
        _buyWhale(who, 5);
        uint256 word = _order(who);
        assertEq(_customCount(word), 5, "one box per pass bought");
        assertEq(_customSize(word), 0.24 ether, "each box is 10% of one pass");
        assertEq(_coverWei(word), 0, "nothing lands in the cover lane");
    }

    /// @notice 100 passes queue 120 passes' entries but only 100 boxes: the bonus is entries.
    function testBonusPassesAddNoBox() public {
        address who = makeAddr("hundred");
        _buyWhale(who, 100);
        uint256 word = _order(who);
        assertEq(_customCount(word), 100, "boxes follow money in, not bonus passes");
        assertEq(_customSize(word), 0.24 ether, "box size is per paid pass");
    }

    function testSameIndexPurchasesAddTheirCounts() public {
        address who = makeAddr("twice");
        _buyWhale(who, 3);
        _buyWhale(who, 4);
        assertEq(_customCount(_order(who)), 7, "counts add across purchases in one index");
    }

    /// @notice A held custom of another size folds in: count adds, size averages by value.
    function testHeldCustomOfAnotherSizeAveragesIn() public {
        address who = makeAddr("mismatch");
        _buyCustoms(who, 1); // one 0.01 ETH custom
        _buyWhale(who, 3); // 0.72 ETH over three boxes
        uint256 word = _order(who);
        assertEq(_customCount(word), 4, "held custom plus three pass boxes");
        assertEq(_customSize(word), _avg(0.73 ether, 4), "size is the value-weighted average");
    }

    /// @notice A held custom of the SAME size merges: the pass adds to the count.
    function testHeldCustomOfTheSameSizeMerges() public {
        address who = makeAddr("match");
        vm.deal(who, 1 ether + 0.24 ether);
        vm.prank(who);
        game.purchase{value: 1 ether + 0.24 ether}(who, 400, BoxOrderLib.boOrder(0, 0, 0, 1, 0.24 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        _buyWhale(who, 2);
        uint256 word = _order(who);
        assertEq(_customCount(word), 3, "bought custom plus two pass boxes");
        assertEq(_customSize(word), 0.24 ether, "same size stays");
    }

    /// @notice Near the cap the passes land as fewer, larger boxes: 96 held, 5 passes -> 4 boxes.
    function testNearTheCapScalesBoxesUp() public {
        address who = makeAddr("cap");
        _buyWhale(who, 96);
        _buyWhale(who, 5);
        uint256 word = _order(who);
        assertEq(_customCount(word), 100, "filled to the cap");
        // 96 x 0.24 + 1.2 = 24.24 ETH over 100 boxes
        assertEq(_customSize(word), _avg(24.24 ether, 100), "average size scaled up");
    }

    /// @notice At the cap a pass adds no box: its value folds into the held customs.
    function testAtTheCapFoldsIntoHeldCustoms() public {
        address who = makeAddr("full");
        _buyCustoms(who, 100);
        _buyWhale(who, 5);
        uint256 word = _order(who);
        assertEq(_customCount(word), 100, "never past the cap");
        assertEq(_customSize(word), _avg(2.2 ether, 100), "value-weighted average");
        assertEq(_coverWei(word), 0, "the cover lane stays untouched");
    }

    /// @notice Two calls of 100 in one index: the second folds its value into the first's boxes.
    function testTwoHundredPassesInOneIndex() public {
        address who = makeAddr("twohundred");
        _buyWhale(who, 100);
        _buyWhale(who, 100);
        uint256 word = _order(who);
        assertEq(_customCount(word), 100, "still 100 boxes");
        assertEq(_customSize(word), _avg(48 ether, 100), "both purchases' value, averaged");
    }

    /// @notice A full entry with no custom to fold into is the one refusal.
    function testFullPresetEntryWithNoCustomReverts() public {
        address who = makeAddr("presets");
        vm.deal(who, 20 ether);
        vm.prank(who);
        game.purchase{value: 20 ether}(who, 400, BoxOrderLib.boOrder(100, 0, 0, 0, 0), bytes32(0), MintPaymentKind.DirectEth, false);
        vm.deal(who, 2.4 ether);
        vm.prank(who);
        vm.expectRevert();
        game.purchaseWhalePass{value: 2.4 ether}(who, 1, bytes32(0));
    }

    function testLazyPassRecordsOneBox() public {
        address who = makeAddr("lazy");
        vm.deal(who, 1 ether);
        vm.prank(who);
        game.purchaseLazyPass{value: 0.24 ether}(who, bytes32(0));
        uint256 word = _order(who);
        assertEq(_customCount(word), 1, "one box for one pass");
        assertEq(_customSize(word), 0.024 ether, "10% of the lazy pass");
    }

    function testFuzzCountEqualsQuantity(uint256 q) public {
        q = bound(q, 1, 100);
        address who = makeAddr("fuzz");
        _buyWhale(who, q);
        uint256 word = _order(who);
        assertEq(_customCount(word), q, "count = passes bought");
        assertEq(_customSize(word), 0.24 ether, "size = 10% of one pass");
    }
}
