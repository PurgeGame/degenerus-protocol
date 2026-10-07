// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

/// @title PassBoxAutoOpenEnqueue — WHALE-01: pass-bundled lootboxes must enqueue for auto-open
/// @notice Mint, presale, afking-cover and pass-bundled lootboxes all append an entry to the
///         write buffer's box queue, which the mineFlip HumanBoxes stage settles in FIFO order.
///         A pass-bundled box recorded but NOT queued could be held closed by its owner
///         and opened at a favorable live level/boon state, defeating the "permissionless
///         economically-incentivized open" premise of the lootbox-resolution-timing ruling.
///
///         This drives the REAL whale-pass purchase and asserts the box is appended to the queue
///         as its own entry carrying the buyer's wallet ID.
/// @dev Test-only. No contracts/*.sol is mutated. The entry is read through the queue's storage
///      location (RecyclingState.boxEntry / boxCount).
contract PassBoxAutoOpenEnqueue is DeployProtocol {
    using BoxOrderLib for uint256;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 100e18);
    }

    function test_WhalePassBox_IsEnqueuedForAutoOpen() public {
        address buyer = makeAddr("whaleBuyer");
        vm.deal(buyer, 10 ether);

        uint48 idx = RecyclingState.writeBuffer(address(game));
        uint256 before = RecyclingState.boxCount(address(game), idx);

        // Whale pass at level 0: passLevel = 1 -> early price 2.4 ETH, quantity 1, no century gate.
        // The pass deposits a 10%-of-price lootbox via _recordLootboxEntry.
        vm.prank(buyer);
        game.purchaseWhalePass{value: 2.4 ether}(0, 1, bytes32(0));

        assertEq(
            RecyclingState.boxCount(address(game), idx),
            before + 1,
            "WHALE-01: the pass-bundled lootbox must be appended to the auto-open queue"
        );
        uint256 word = RecyclingState.boxEntry(address(game), idx, before);
        assertEq(word.boId(), game.walletIdOf(buyer), "the queued entry is the buyer's");
        assertEq(word.boCount(), 1, "one box for one pass");
        assertEq(word.boSizeWei(), 0.24 ether, "the box is 10% of the pass");
    }
}
