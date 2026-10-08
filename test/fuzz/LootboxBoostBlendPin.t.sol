// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title LootboxBoostBlendPin -- the boost lane of a box entry belongs to its own purchase
/// @notice A lootbox boon lifts ONE purchase's spend. Every purchase is its own queue entry, so
///         the entry that consumed the boon carries its lift as a fraction of its own spend, and
///         a later purchase neither inherits that lift nor erases it. Pinned because the v78
///         mutation campaign showed the boost write had no test on it.
contract LootboxBoostBlendPin is DeployProtocol {
    using BoxOrderLib for uint256;

    uint256 constant SLOT_BOON_PACKED = GameSlots.BOON_PACKED;
    uint256 constant BP_LOOTBOX_TIER_SHIFT = 104;
    /// @dev Tier-1 lootbox boost (`_lootboxTierToBps(1)`).
    uint256 constant TIER1_BOOST_BPS = 500;

    address internal player = makeAddr("blendPlayer");
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        _completeDay(0xB1E4D001);
        vm.deal(player, 100 ether);
    }

    function _completeDay(uint256 vrfWord) internal {
        _finishReadConsumers();
        game.mineFlip(0);
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.mineFlip(0);
        }
        _finishReadConsumers();
    }

    function _lrIndex() internal view returns (uint48) {
        return RecyclingState.writeBuffer(address(game));
    }

    function _giveLootboxBoon(address who) internal {
        uint32 id = game.walletIdOf(who);
        if (id == 0) id = _giveWalletId(who);
        bytes32 slot = keccak256(abi.encode(uint256(id), SLOT_BOON_PACKED));
        uint256 s0 = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(s0 | (uint256(1) << BP_LOOTBOX_TIER_SHIFT)));
    }

    /// @dev `n` custom boxes of `amount` each; returns the entry's position in `idx`.
    function _buyBoxes(uint48 idx, uint256 n, uint256 amount) internal returns (uint256 position) {
        position = RecyclingState.boxCount(address(game), idx);
        vm.prank(player);
        game.purchase{value: n * amount + 1 ether}(
            0, 400, BoxOrderLib.boCustoms(n, amount), bytes32(0), MintPaymentKind.DirectEth, false
        );
        assertEq(RecyclingState.boxCount(address(game), idx), position + 1, "one entry per purchase");
    }

    function _buyBox(uint48 idx, uint256 amount) internal returns (uint256) {
        return _buyBoxes(idx, 1, amount);
    }

    function _entry(uint48 idx, uint256 position) internal view returns (uint256) {
        return RecyclingState.boxEntry(address(game), idx, position);
    }

    /// @notice The boon lifts the purchase that consumes it, as a fraction of that purchase's own
    ///         spend; a later purchase in the same buffer carries no lift and leaves the boosted
    ///         entry untouched.
    function test_boonLiftsOnlyThePurchaseThatConsumesIt() public {
        uint48 idx = _lrIndex();
        uint256 size = 0.05 ether;

        _giveLootboxBoon(player);
        uint256 p1 = _buyBox(idx, size);
        uint256 first = _entry(idx, p1);
        assertEq(first.boBoostBps(), TIER1_BOOST_BPS, "the boon lifted the first purchase by its tier");
        assertEq(_lrIndex(), idx, "same buffer for the second purchase");

        uint256 p2 = _buyBoxes(idx, 3, size);
        assertEq(p2, p1 + 1, "the second purchase is the next entry");
        assertEq(_entry(idx, p2).boBoostBps(), 0, "the one-shot boon does not lift a second purchase");
        assertEq(_entry(idx, p1), first, "the earlier lift is not discarded");
    }

    /// @notice `applyBoxOrderScore` writes the buyer's post-action activity score into the entry's
    ///         score lane. A purchase that leaves the lane empty would resolve every box at the
    ///         curve's floor.
    function test_purchaseFoldsTheScoreLane() public {
        uint48 idx = _lrIndex();
        uint256 word = _entry(idx, _buyBox(idx, 0.05 ether));
        assertTrue(word != 0, "the entry was recorded");
        assertGt(word.boScore(), 0, "the score lane was written");
    }

    function test_orderWithoutAnyBoonHasAnEmptyBoostLane() public {
        uint48 idx = _lrIndex();
        uint256 p1 = _buyBox(idx, 0.05 ether);
        uint256 p2 = _buyBox(idx, 0.05 ether);
        assertEq(_entry(idx, p1).boBoostBps(), 0, "no boon, no lift");
        assertEq(_entry(idx, p2).boBoostBps(), 0, "no boon, no lift");
    }
}
