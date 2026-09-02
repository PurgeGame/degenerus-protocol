// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @title LootboxBoostBlendPin -- the boost lane of a box order blends across purchases
/// @notice A lootbox boon lifts ONE purchase's spend. A second order at the same RNG index does
///         not inherit that lift whole and does not lose it: the order word's boost lane is the
///         nominal-weighted average of the two purchases, so the resolver scales each box by the
///         fraction of the whole order that was actually boosted. Pinned because the v78 mutation
///         campaign showed the blend write had no test on it.
contract LootboxBoostBlendPin is DeployProtocol {
    uint256 constant SLOT_BOON_PACKED = 50;
    uint256 constant SLOT_LOOTBOX_ETH = 15;
    uint256 constant SLOT_LOOTBOX_RNG_IDX = 33;
    uint256 constant LB_BOOST_SHIFT = 39;
    uint256 constant LB_BPS_MASK = 0x3FFF;
    uint256 constant BP_LOOTBOX_TIER_SHIFT = 104;

    address internal player = makeAddr("blendPlayer");
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        _completeDay(0xB1E4D001);
        vm.deal(player, 100 ether);
    }

    function _completeDay(uint256 vrfWord) internal {
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
    }

    function _lrIndex() internal view returns (uint48) {
        return uint48(uint256(vm.load(address(game), bytes32(SLOT_LOOTBOX_RNG_IDX))) & 0xFFFFFFFFFFFF);
    }

    function _orderWord(uint48 index, address who) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(uint256(index), SLOT_LOOTBOX_ETH));
        return uint256(vm.load(address(game), keccak256(abi.encode(who, inner))));
    }

    function _boostLane(uint256 word) internal pure returns (uint256) {
        return (word >> LB_BOOST_SHIFT) & LB_BPS_MASK;
    }

    function _giveLootboxBoon(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, SLOT_BOON_PACKED));
        uint256 s0 = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(s0 | (uint256(1) << BP_LOOTBOX_TIER_SHIFT)));
    }

    /// @dev `n` custom boxes of `amount` each. The custom size freezes on an index's first order,
    ///      so a later order at the same index adds boxes of that size.
    function _buyBoxes(uint256 n, uint256 amount) internal {
        vm.prank(player);
        game.purchase{value: n * amount + 1 ether}(
            player, 400, BoxOrderLib.boCustoms(n, amount), bytes32(0), MintPaymentKind.DirectEth, false
        );
    }

    function _buyBox(uint256 amount) internal {
        _buyBoxes(1, amount);
    }

    function test_secondOrderAtTheSameIndexBlendsTheBoostLane() public {
        uint48 idx = _lrIndex();
        uint256 size = 0.05 ether;
        uint256 first = size;
        uint256 second = 3 * size;

        _giveLootboxBoon(player);
        _buyBox(size);
        uint256 lane1 = _boostLane(_orderWord(idx, player));
        assertGt(lane1, 0, "the boon lifted the first purchase");
        assertEq(_lrIndex(), idx, "same index for the second order");

        _buyBoxes(3, size);
        uint256 lane2 = _boostLane(_orderWord(idx, player));
        // Weighted by nominal: the unboosted second purchase dilutes the lane, never zeroes it
        // and never carries the first purchase's lift whole.
        uint256 expected = (lane1 * first) / (first + second);
        assertApproxEqAbs(lane2, expected, 1, "boost lane is the nominal-weighted blend");
        assertLt(lane2, lane1, "an unboosted purchase dilutes the lane");
        assertGt(lane2, 0, "the earlier lift is not discarded");
    }

    /// @notice `applyBoxOrderScore` folds the buyer's activity score into the order word's score
    ///         lane on the period's first box. A purchase that leaves the lane empty would resolve
    ///         every box at the curve's floor.
    function test_purchaseFoldsTheScoreLane() public {
        uint48 idx = _lrIndex();
        _buyBox(0.05 ether);
        uint256 word = _orderWord(idx, player);
        assertTrue(word != 0, "the order was recorded");
        assertGt((word >> 24) & 0x7FFF, 0, "the score lane was folded on the first box");
    }

    function test_orderWithoutAnyBoonHasAnEmptyBoostLane() public {
        uint48 idx = _lrIndex();
        _buyBox(0.05 ether);
        _buyBox(0.05 ether);
        assertEq(_boostLane(_orderWord(idx, player)), 0, "no boon, no lift");
    }
}
