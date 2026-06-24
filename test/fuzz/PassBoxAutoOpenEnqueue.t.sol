// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";

/// @dev Read-only view overlay etched onto the live game to inspect internal box-queue state.
contract BoxQueueViewer is DegenerusGame {
    function lrIndexView() external view returns (uint48) {
        return uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK));
    }

    function boxPlayersContains(uint48 index, address who) external view returns (bool) {
        address[] storage q = boxPlayers[index];
        for (uint256 i; i < q.length; ++i) {
            if (q[i] == who) return true;
        }
        return false;
    }

    function lootboxAmountFor(uint48 index, address who) external view returns (uint256) {
        return lootboxEth[index][who] & LB_AMOUNT_MASK;
    }
}

/// @title PassBoxAutoOpenEnqueue — WHALE-01: pass-bundled lootboxes must enqueue for auto-open
/// @notice Mint, presale, and afking-cover lootboxes are enqueued into boxPlayers[index] so the
///         permissionless openBoxes() auto-opener resolves them. Pass-bundled lootboxes
///         (whale/lazy/deity, created in WhaleModule._recordLootboxEntry) were NOT enqueued, so
///         their owner — the only party who can open them (manual openLootBox is operator-gated) —
///         could hold the box closed and time the open to a favorable live level/boon state. That
///         defeats the "permissionless economically-incentivized open" premise of the
///         lootbox-resolution-timing by-design ruling for this one box class.
///
///         This drives the REAL whale-pass purchase and asserts the box is enqueued for
///         auto-open. PRE-FIX the buyer is absent from boxPlayers[index] and this FAILS; POST-FIX it
///         is present and this PASSES.
/// @dev Test-only. No contracts/*.sol is mutated. A read-only viewer is etched (type().runtimeCode,
///      no constructor) to inspect the internal boxPlayers/lootboxEth maps, then real code restored.
contract PassBoxAutoOpenEnqueue is DeployProtocol {
    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 100e18);
    }

    function test_WhalePassBox_IsEnqueuedForAutoOpen() public {
        address buyer = makeAddr("whaleBuyer");
        vm.deal(buyer, 10 ether);

        // Whale pass at level 0: passLevel = 1 -> early price 2.4 ETH, quantity 1, no century gate.
        // The pass deposits a 10%-of-price lootbox via _recordLootboxEntry.
        vm.prank(buyer);
        game.purchaseWhalePass{value: 2.4 ether}(buyer, 1);

        // Inspect internal box-queue state via an etched read-only viewer (no storage change).
        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(BoxQueueViewer).runtimeCode);
        uint48 idx = BoxQueueViewer(payable(address(game))).lrIndexView();
        uint256 boxAmt = BoxQueueViewer(payable(address(game))).lootboxAmountFor(idx, buyer);
        bool enqueued = BoxQueueViewer(payable(address(game))).boxPlayersContains(idx, buyer);
        vm.etch(address(game), realCode);

        assertGt(boxAmt, 0, "fixture: whale pass created a lootbox box at the active index");
        assertTrue(
            enqueued,
            "WHALE-01: pass-bundled lootbox must be enqueued for the permissionless auto-open (else the owner can hold + time the open)"
        );
    }
}
