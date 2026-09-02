// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @dev Reads the packed lootbox RNG word's lanes through the game's own storage layout.
contract LaneViewer is DegenerusGame {
    function lanes() external view returns (uint48 index, uint64 pendingMilliEth, uint64 thresholdMilliEth, uint40 pendingFlip) {
        uint256 w = lootboxRngPacked;
        index = uint48((w >> LR_INDEX_SHIFT) & LR_INDEX_MASK);
        pendingMilliEth = uint64((w >> LR_PENDING_ETH_SHIFT) & LR_PENDING_ETH_MASK);
        thresholdMilliEth = uint64((w >> LR_THRESHOLD_SHIFT) & LR_THRESHOLD_MASK);
        pendingFlip = uint40((w >> LR_PENDING_FLIP_SHIFT) & LR_PENDING_FLIP_MASK);
    }
}

/// @title LootboxPendingEthLane -- a box order, or a pass's cover box, adds exactly its cost in milli-ETH to the pending lane
/// @notice `beginBoxOrder` packs the order's ETH cost into the 64-bit pending-ETH lane of
///         `lootboxRngPacked` (bits 48..111), which is what the mid-day RNG request's threshold
///         gate reads. Mutation v78 rewrote that pack five different ways (`>>` to `/`, `&` to
///         `/`, `<<` to `-`, `<<` to `/`, `&` to `%`) and every one survived: the gating suites
///         assert the gate's behaviour, never the lane's figure. `recordCoverBox` — the pass
///         purchases' cover box — packs the same lane with the same arithmetic on its own path.
///         This reads the lane before and after two orders and two pass buys, and checks the
///         neighbouring lanes stayed put.
contract LootboxPendingEthLane is DeployProtocol {
    address internal actor;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 100e18);
        actor = makeAddr("laneActor");
        vm.deal(actor, 100 ether);
    }

    function _lanes() internal returns (uint48 index, uint64 pending, uint64 threshold, uint40 flip) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(LaneViewer).runtimeCode);
        (index, pending, threshold, flip) = LaneViewer(payable(address(game))).lanes();
        vm.etch(address(game), real);
    }

    function test_boxOrderCostLandsInThePendingEthLane() public {
        (, , , , uint256 priceWei) = game.purchaseInfo();
        (uint48 idx0, uint64 pend0, uint64 thr0, uint40 flip0) = _lanes();

        // Two smalls and a 0.5 ETH custom: cost is the order's nominal.
        uint256 cost1 = 2 * priceWei + 0.5 ether;
        vm.prank(actor);
        game.purchase{value: cost1 + 1 ether}(
            actor, 400, BoxOrderLib.boOrder(2, 0, 0, 1, 0.5 ether), bytes32(0), MintPaymentKind.DirectEth, false
        );
        (uint48 idx1, uint64 pend1, uint64 thr1, uint40 flip1) = _lanes();
        assertEq(idx1, idx0, "the index lane is untouched by a buy");
        assertEq(thr1, thr0, "the threshold lane is untouched by a buy");
        assertEq(flip1, flip0, "the pending-FLIP lane is untouched by an ETH buy");
        assertEq(uint256(pend1) - uint256(pend0), cost1 / 1e15, "the pending lane grew by the order's cost in milli-ETH");

        // A second order at the same index accumulates.
        uint256 cost2 = 3 * 5 * priceWei;
        vm.prank(actor);
        game.purchase{value: cost2 + 1 ether}(
            actor, 400, BoxOrderLib.boOrder(0, 3, 0, 0, 0), bytes32(0), MintPaymentKind.DirectEth, false
        );
        (uint48 idx2, uint64 pend2, uint64 thr2,) = _lanes();
        assertEq(idx2, idx0, "still the same index");
        assertEq(thr2, thr0, "threshold still untouched");
        assertEq(uint256(pend2) - uint256(pend1), cost2 / 1e15, "the second order adds its own cost");
    }

    /// @notice A whale pass and a lazy pass each record a cover box worth 10% of the pass price
    ///         (`WHALE_LOOTBOX_BPS`, `LAZY_PASS_LOOTBOX_BPS`) through `recordCoverBox`, which
    ///         packs the pending lane on its own path.
    function test_passCoverBoxesLandInThePendingEthLane() public {
        (uint48 idx0, uint64 pend0, uint64 thr0, uint40 flip0) = _lanes();

        vm.prank(actor);
        game.purchaseWhalePass{value: 2.4 ether}(actor, 1, bytes32(0));
        (uint48 idx1, uint64 pend1, uint64 thr1, uint40 flip1) = _lanes();
        assertEq(idx1, idx0, "the index lane is untouched by a pass buy");
        assertEq(thr1, thr0, "the threshold lane is untouched");
        assertEq(flip1, flip0, "the pending-FLIP lane is untouched");
        assertEq(uint256(pend1) - uint256(pend0), (2.4 ether / 10) / 1e15, "a whale pass covers 10% of its price into the lane");

        // A pass holder cannot buy a lazy pass on top, so a second wallet buys it.
        address lazy = makeAddr("lazyActor");
        vm.deal(lazy, 10 ether);
        vm.prank(lazy);
        game.purchaseLazyPass{value: 0.24 ether}(lazy, bytes32(0));
        (uint48 idx2, uint64 pend2, uint64 thr2,) = _lanes();
        assertEq(idx2, idx0, "still the same index");
        assertEq(thr2, thr0, "threshold still untouched");
        assertEq(uint256(pend2) - uint256(pend1), (0.24 ether / 10) / 1e15, "a lazy pass covers 10% of its price into the lane");
    }
}
