// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title StallResilience -- Proves VRF stall -> coordinator swap -> resume cycle
/// @notice Integration tests for gap day RNG backfill (TEST-01), coinflip resolution
///         across gap days (TEST-02), and lootbox opens on a swap-reissued index (TEST-03).
///         A stalled request's late word finishes the day it was sent for; the wall day's
///         fresh request then derives the skipped days in between.
contract StallResilience is DeployProtocol {
    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // ── Helpers ──────────────────────────────────────────────────────

    /// @dev Complete a full day: mineFlip -> VRF fulfill -> loop until unlocked.
    function _completeDay(uint256 vrfWord) internal {
        _finishReadConsumers();
        game.mineFlip(0);
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, vrfWord);
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.mineFlip(0);
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
        game.updateVrfCoordinatorAndSub(address(newVRF), newSubId, bytes32(uint256(1)));
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
        try game.mineFlip(0) {
            return true;
        } catch (bytes memory err) {
            bytes4 sel = bytes4(err);
            assertTrue(sel == RNG_NOT_READY || sel == NO_WORK, "engine stopped on an unexpected error");
            return false;
        }
    }

    /// @dev Resume after coordinator swap. The swap re-issues the in-flight request on the
    ///      new coordinator (preserve+re-issue), so a pending request already exists. Fulfil
    ///      it first so the re-issued word is delivered, then drain via mineFlip until the
    ///      stalled day is sealed. The composed mineFlip that seals it may go straight on to
    ///      the wall day's fresh request (the engine selects the next action in the same
    ///      call), so the loop stops on the seal, not on the lock.
    ///      If nothing was in flight (no re-issue), mineFlip fires a fresh request which
    ///      is then fulfilled.
    function _resumeAfterSwap(MockVRFCoordinator newVRF, uint256 vrfWord) internal {
        uint256 reqId = newVRF.lastRequestId();
        if (reqId == 0) {
            game.mineFlip(0);
            reqId = newVRF.lastRequestId();
        }
        uint24 sealedBefore = _dailyIdx();
        newVRF.fulfillRandomWords(reqId, vrfWord);
        for (uint256 i = 0; i < 50; i++) {
            if (_dailyIdx() > sealedBefore) return;
            if (!_step()) break;
        }
        assertGt(_dailyIdx(), sealedBefore, "the re-issued word sealed the stalled day");
    }

    /// @dev Catch up after the stalled day finished: the wall day's fresh request is answered
    ///      with `word`, which derives the skipped days in between, and the wall day completes.
    function _catchUp(MockVRFCoordinator vrf, uint256 word) internal {
        uint24 wallDay = game.currentDayView();
        for (uint256 i = 0; i < 60; i++) {
            uint256 id = vrf.lastRequestId();
            if (id != 0) {
                (,, bool done) = vrf.pendingRequests(id);
                if (!done) vrf.fulfillRandomWords(id, word);
            }
            if (!game.rngLocked() && game.rngWordForDay(wallDay) != 0) return;
            _step();
        }
        fail("catch-up did not complete the wall day");
    }

    // ── TEST-01: Stall -> Swap -> Resume with gap day backfill ───────

    /// @notice Proves the stalled day finishes on its own (swap-reissued) word and the
    ///         skipped days get words derived from the wall day's fresh VRF word via
    ///         keccak256(vrfWord, gapDay).
    function test_stallSwapResume() public {
        // Complete the first post-deploy day normally
        _completeDay(0xDEAD0001);
        assertEq(game.currentDayView(), 2);
        assertTrue(game.rngWordForDay(2) != 0, "Day 2 has RNG word");

        // Warp to the next day, trigger VRF request (this will stall)
        vm.warp(block.timestamp + 1 days);
        game.mineFlip(0);
        assertTrue(game.rngLocked(), "Day 3 VRF request pending");

        // Stall: warp +3 days without fulfilling (gap days: 3, 4, 5; current day after warp: 6)
        MockVRFCoordinator newVRF = _stallAndSwap(3);

        // The swap re-sent day 3's request; its late word finishes day 3 (no gap yet).
        _resumeAfterSwap(newVRF, 0xCAFE0003);
        // rngWordForDay retains only today and yesterday (c729ecfc9), and the wall day is 6:
        // read day 3's exact-tag ring entry, which the wall day's request has not yet replaced.
        assertEq(RecyclingState.dailyWord(address(game), 3), 0xCAFE0003, "Stalled day 3 finishes on its own word");
        assertEq(game.rngWordForDay(4), 0, "Day 4 not derived before the wall day's request");
        assertEq(game.rngWordForDay(5), 0, "Day 5 not derived before the wall day's request");

        // Day 6's fresh request derives the skipped days 4 and 5 (TEST-01 core assertion).
        uint256 resumeWord = 0xCAFEBABE;
        _catchUp(newVRF, resumeWord);
        // The two-slot daily ring retains only the final gap day's derived word next to the
        // wall day's (6d0e64b09 / c729ecfc9: _backfillGapDays "retain just the last derived
        // word"); every gap day is still settled, through its coinflip day.
        assertEq(game.rngWordForDay(4), 0, "Gap day 4 keeps no word: only the final gap day is retained");
        assertEq(RecyclingState.dailyWord(address(game), 4), 0, "Gap day 4 has no ring entry");
        assertTrue(game.rngWordForDay(5) != 0, "Gap day 5 backfilled");
        assertTrue(game.rngWordForDay(6) != 0, "Current day 6 processed");
        (uint16 reward4,) = coinflip.getCoinflipDayResult(4);
        (uint16 reward5,) = coinflip.getCoinflipDayResult(5);
        assertTrue(reward4 != 0, "Gap day 4 still settles (coinflip)");
        assertTrue(reward5 != 0, "Gap day 5 still settles (coinflip)");

        // Gap words derive from the raw VRF word (backfill runs before _applyDailyRng), with
        // the day packed as uint24 (the backfill loop counter type).
        uint256 expectedDay5 = uint256(keccak256(abi.encodePacked(resumeWord, uint24(5))));
        if (expectedDay5 == 0) expectedDay5 = 1;
        assertEq(game.rngWordForDay(5), expectedDay5, "Day 5 word is keccak256(vrfWord, 5)");
    }

    // ── TEST-02: Coinflip claims across gap days ────────────────────

    /// @notice Proves coinflip stakes placed before/during stall resolve after
    ///         backfill -- getCoinflipDayResult returns non-zero rewardPercent
    ///         for each gap day.
    function test_coinflipClaimsAcrossGapDays() public {
        // Setup buyer
        address buyer = makeAddr("flipBuyer");
        vm.deal(buyer, 100 ether);

        // Purchase 5 tickets before completing the first post-deploy day
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(buyer);
            game.purchase{value: 0.01 ether}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        }

        // Complete the first post-deploy day (day 2)
        _completeDay(0xF11F0001);

        // Warp to the next day (day 3), trigger VRF request (will stall)
        vm.warp(block.timestamp + 1 days);
        game.mineFlip(0);
        assertTrue(game.rngLocked(), "Day 3 VRF pending");

        // Purchase during stall at day 3 (stakes go to day 4)
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(buyer);
            game.purchase{value: 0.01 ether}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        }

        // Warp +1 day (still stalled), purchase at day 4 (stakes go to day 5)
        vm.warp(block.timestamp + 1 days);
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(buyer);
            game.purchase{value: 0.01 ether}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        }

        // Warp +2 more days to create the full gap (now at day 6)
        vm.warp(block.timestamp + 2 days);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Resume: the reissued request's word settles day 3; day 6's fresh request derives
        // and settles the skipped days 4 and 5.
        _resumeAfterSwap(newVRF, 0xF11FCAFE);
        _catchUp(newVRF, 0xF11FCAFF);

        // processCoinflipPayouts always writes coinflipDayResult (rewardPercent >= 50).
        (uint16 reward3,) = coinflip.getCoinflipDayResult(3);
        (uint16 reward4,) = coinflip.getCoinflipDayResult(4);
        (uint16 reward5,) = coinflip.getCoinflipDayResult(5);

        assertTrue(reward3 != 0, "Day 3 coinflip resolved after backfill");
        assertTrue(reward4 != 0, "Day 4 coinflip resolved after backfill");
        assertTrue(reward5 != 0, "Day 5 coinflip resolved after backfill");
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
        game.purchase{value: 1.01 ether}(0, 400, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);

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
        game.purchase{value: 1.01 ether}(0, 400, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);

        // mineFlip triggers VRF request, which reserves lootbox index preStallIndex (2)
        // and increments lootboxRngIndex to 3
        game.mineFlip(0);
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
        game.mineFlip(0);
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
        assertEq(BoxOrderLib.boId(entry), game.walletIdOf(buyer), "the entry belongs to the buyer");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool opened;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(game) && logs[i].topics.length > 1
                && (logs[i].topics[0] == keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)")
                    || logs[i].topics[0] == keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)"))
                && uint32(uint256(logs[i].topics[1])) == game.walletIdOf(buyer)) opened = true;
        }
        assertTrue(opened, "the stalled cohort's box opened on the reissued word");
    }
}
