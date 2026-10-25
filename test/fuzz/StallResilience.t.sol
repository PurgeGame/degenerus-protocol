// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title StallResilience -- Proves VRF stall -> coordinator swap -> resume cycle
/// @notice Integration test for lootbox opens on a swap-reissued index (TEST-03). A stalled
///         request's late word finishes the day it was sent for. Gap-day backfill and coinflip
///         resolution across gap days no longer exist: a stall creates no logical days.
contract StallResilience is DeployProtocol {
    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // ── Helpers ──────────────────────────────────────────────────────

    /// @dev Complete a full day: mineFlip -> VRF fulfill -> loop until unlocked.
    function _completeDay(uint256 vrfWord) internal {
        _finishReadConsumers();
        game.mineRun(0);
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, vrfWord);
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.mineRun(0);
        }
        _finishReadConsumers();
    }

    /// @dev Read lootboxRngIndex from lootboxRngPacked (storage slot 34, low bits = LR_INDEX)
    ///      (post V62 lootbox repack: was 35).
    function _lootboxRngIndex() internal view returns (uint48) {
        return RecyclingState.writeBuffer(address(game));
    }

    /// @dev Read _lootboxWord(index) from storage (mapping at slot 34, post V62 repack: was 36).
    function _lootboxRngWord(uint48 index) internal view returns (uint256) {
        return RecyclingState.word(address(game), index);
    }

    /// @dev Deploy a new MockVRFCoordinator, wire it up, and call
    ///      updateVrfCoordinatorAndSub via admin prank. No time warp.
    function _doCoordinatorSwap() internal returns (MockVRFCoordinator newVRF) {
        newVRF = new MockVRFCoordinator();
        uint256 newSubId = newVRF.createSubscription();
        newVRF.addConsumer(newSubId, address(game));
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(newVRF), newSubId, bytes32(uint256(1)), 300_000);
    }

    /// @dev Warp forward by gapDays, then do coordinator swap.
    function _stallAndSwap(uint256 gapDays) internal returns (MockVRFCoordinator newVRF) {
        vm.warp(block.timestamp + gapDays * 1 days);
        return _doCoordinatorSwap();
    }

    bytes4 private constant RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));
    bytes4 private constant NO_WORK = bytes4(keccak256("NoWork()"));

    /// @dev Read dailyIdx (slot 0, uint24 at bit offset 24).
    function _dailyIdx() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(0))) >> 24);
    }

    /// @dev One engine step. The miner's explicit stop signals (waiting on a word, nothing to
    ///      do) end a drive loop; any other revert is a real failure and fails the test.
    function _step() internal returns (bool moved) {
        try game.mineRun(0) {
            return true;
        } catch (bytes memory err) {
            bytes4 sel = bytes4(err);
            assertTrue(sel == RNG_NOT_READY || sel == NO_WORK, "engine stopped on an unexpected error");
            return false;
        }
    }

    // ── TEST-03: Lootbox open after orphaned index backfill ─────────

    /// @notice Proves the lootbox index reserved by a stalled daily request gets a word once
    ///         the swap-reissued request is answered, and the engine opens the box on that word.
    function test_lootboxOpenAfterOrphanedIndexBackfill() public {
        // Setup buyer with enough ETH for lootbox purchases
        address buyer = makeAddr("lootBuyer");
        vm.deal(buyer, 200 ether);

        // Day 1: purchase with lootbox amount
        // lootboxRngIndex = 1, so this writes to lootboxEth[1][buyer]
        vm.prank(buyer);
        game.purchaseOrderFor{value: 1.01 ether}(0, 400, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);

        // Complete day 1 (VRF request reserves lootbox index 1, fulfillment writes word for index 1)
        // After this: lootboxRngIndex = 2
        _completeDay(0x10070001);

        // Record the current lootbox index (should be 2 now)
        uint48 preStallIndex = _lootboxRngIndex();

        // Warp to day 2
        vm.warp(block.timestamp + 1 days);

        // Purchase with lootbox amount BEFORE mineFlip so lootboxEth[preStallIndex][buyer] has value
        // lootboxRngIndex is still preStallIndex (2), so this writes to lootboxEth[2][buyer]
        vm.prank(buyer);
        game.purchaseOrderFor{value: 1.01 ether}(0, 400, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);

        // mineFlip triggers VRF request, which reserves lootbox index preStallIndex (2)
        // and increments lootboxRngIndex to 3
        game.mineRun(0);
        assertTrue(game.rngLocked(), "Day 2 VRF pending");

        // The stalled request reserved preStallIndex
        uint48 orphanedIndex = preStallIndex;

        // Verify no RNG word yet for orphaned index
        assertEq(_lootboxRngWord(orphanedIndex), 0, "Orphaned index has no RNG word before swap");

        // Stall + swap: the swap re-sends the request for the same reserved index
        MockVRFCoordinator newVRF = _stallAndSwap(3);
        // Two physical buffers (6d0e64b09): the request sealed preStallIndex as the read side.
        assertEq(_lootboxRngIndex(), preStallIndex ^ 1, "Swap keeps the reserved index");
        assertEq(_lootboxRngWord(orphanedIndex), 0, "Reserved index has no word before the reissued word");

        // Resume: the reissued request's word finalizes the reserved index. Publication is the
        // first action of the next call, before any consumer reads the word.
        newVRF.fulfillRandomWords(newVRF.lastRequestId(), 0x1007CAFE);
        vm.recordLogs();
        game.mineRun(0);
        assertTrue(_lootboxRngWord(orphanedIndex) != 0, "Reserved index finalized by the reissued word");

        // The engine steps on that index without an unexpected error, and the box bought into
        // the stalled cohort resolves on that word in the engine's human-box stage, which must
        // finish before any later request may retire the buffer: its queue entry opens
        // (the open reports an event indexed by the buyer).
        uint24 sealedBefore = _dailyIdx();
        for (uint256 i = 0; i < 50 && _dailyIdx() == sealedBefore; i++) {
            if (!_step()) break;
        }
        assertGt(_dailyIdx(), sealedBefore, "the stalled day sealed");
        uint256 entry = RecyclingState.boxEntry(address(game), orphanedIndex & 1, 0);
        assertTrue(entry != 0, "the stalled cohort's box entry exists");
        assertEq(BoxOrderLib.boId(entry), game.walletIdOf_g3120(buyer), "the entry belongs to the buyer");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool opened;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(game) && logs[i].topics.length > 1
                && (logs[i].topics[0] == keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)")
                    || logs[i].topics[0] == keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)"))
                && uint32(uint256(logs[i].topics[1])) == game.walletIdOf_g3120(buyer)) opened = true;
        }
        assertTrue(opened, "the stalled cohort's box opened on the reissued word");
    }
}
