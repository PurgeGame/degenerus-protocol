// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title VRFStallEdgeCases -- Audit tests for VRF stall edge case requirements
/// @notice Covers STALL-01 (gap backfill entropy), STALL-02 (manipulation window),
///         STALL-03 (gas ceiling), STALL-04 (coordinator swap state), STALL-05 (zero-seed),
///         STALL-06 (swap re-issue / V37-001), STALL-07 (dailyIdx timing consistency).
///         A stalled request keeps the day it was sent for: its late word finishes that day,
///         and the next day's fresh request derives the skipped days in between.
contract VRFStallEdgeCases is DeployProtocol {
    /// @dev Storage slot constants verified via `forge inspect DegenerusGame storage-layout`.
    uint256 constant SLOT_PACKED_0 = 0;
    uint256 constant SLOT_RNG_WORD_CURRENT = 3;
    uint256 constant SLOT_VRF_REQUEST_ID = 4;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    /// @dev Complete a full day: mineFlip -> VRF fulfill -> loop until unlocked.
    ///      Tracks the last-known request ID to avoid double-fulfillment when the
    ///      game reuses a stale rngWordCurrent across day boundaries.
    uint256 private _lastFulfilledReqId;

    function _completeDay(uint256 vrfWord) internal {
        _finishReadConsumers();
        game.mineFlip();
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.mineFlip();
        }
            _finishReadConsumers();
    }

    /// @dev Deploy a new MockVRFCoordinator, wire it up via admin prank.
    ///      Resets _lastFulfilledReqId since the new mock has its own request counter.
    function _doCoordinatorSwap() internal returns (MockVRFCoordinator newVRF) {
        newVRF = new MockVRFCoordinator();
        uint256 newSubId = newVRF.createSubscription();
        newVRF.addConsumer(newSubId, address(game));
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(newVRF), newSubId, bytes32(uint256(1)));
        _lastFulfilledReqId = 0;
    }

    /// @dev Warp forward by gapDays, then do coordinator swap.
    function _stallAndSwap(uint256 gapDays) internal returns (MockVRFCoordinator newVRF) {
        vm.warp(block.timestamp + gapDays * 1 days);
        return _doCoordinatorSwap();
    }

    bytes4 private constant RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));
    bytes4 private constant NO_WORK = bytes4(keccak256("NoWork()"));
    uint8 private constant ACTION_DAILY_GAP = 5;
    uint8 private constant ACTION_DAILY_APPLY = 6;

    /// @dev One engine step. The miner's explicit stop signals (waiting on a word, nothing to
    ///      do) end a drive loop; any other revert is a real failure and fails the test.
    function _step() internal returns (bool moved) {
        try game.mineFlip() {
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
    ///      stalled day is sealed. The composed mineFlip that seals it goes straight on to the
    ///      wall day's fresh request when the wall day is later (the engine selects the next
    ///      action in the same call), so the loop stops on the seal, not on the lock.
    ///      If nothing was in flight (no re-issue), mineFlip fires a fresh request which
    ///      is then fulfilled.
    function _resumeAfterSwap(MockVRFCoordinator newVRF, uint256 vrfWord) internal {
        uint256 reqId = newVRF.lastRequestId();
        if (reqId == 0) {
            game.mineFlip();
            reqId = newVRF.lastRequestId();
        }
        uint48 sealedBefore = _readDailyIdx();
        newVRF.fulfillRandomWords(reqId, vrfWord);
        for (uint256 i = 0; i < 50; i++) {
            if (_readDailyIdx() > sealedBefore) return;
            if (!_step()) break;
        }
        assertGt(_readDailyIdx(), sealedBefore, "the re-issued word sealed the stalled day");
    }

    /// @dev Catch up after the stalled day finished: the wall day's fresh request is answered
    ///      with `word`, which derives the final skipped day's word, and the wall day completes.
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

    /// @dev Read lootboxRngIndex directly from storage slot 35 (lower 48 bits of lootboxRngPacked)
    ///      (Stage B packing: lootboxRngPacked = slot 34).
    function _lootboxRngIndex() internal view returns (uint48) {
        return RecyclingState.writeBuffer(address(game));
    }

    /// @dev Read _lootboxWord(index) from storage (mapping at slot 34, Stage B Game pack).
    function _lootboxRngWord(uint48 index) internal view returns (uint256) {
        return RecyclingState.word(address(game), index);
    }

    /// @dev Read rngWordCurrent directly from storage slot 3.
    function _readRngWordCurrent() internal view returns (uint256) {
        return RecyclingState.currentWord(address(game));
    }

    /// @dev Read vrfRequestId directly from storage slot 4.
    function _readVrfRequestId() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SLOT_VRF_REQUEST_ID))));
    }

    /// @dev Read rngRequestTime from packed slot 0, bytes [6:12] (uint48, bit offset 48).
    function _readRngRequestTime() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(SLOT_PACKED_0))));
        return uint48(packed >> 48);
    }

    /// @dev Read the retry-spent flag: rngFlagsAndNudges (slot 0 bytes [30:32]) bit 10.
    function _readRetrySpent() internal view returns (bool) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(SLOT_PACKED_0))));
        return (packed >> 250) & 1 != 0;
    }

    /// @dev Read dailyIdx from packed slot 0, bytes [3:6] (uint24, bit offset 24).
    function _readDailyIdx() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(SLOT_PACKED_0))));
        return uint48(uint24(packed >> 24));
    }

    // ══════════════════════════════════════════════════════════════════════
    // STALL-01: Gap Backfill Entropy Uniqueness
    // ══════════════════════════════════════════════════════════════════════

    /// @dev Delivered words 0 and 1 apply above rngGate's request-sent sentinel (1), so the
    ///      wall day still completes.
    function test_gapBackfillEntropyUnique_sentinelWords() public {
        uint256 snap = vm.snapshotState();
        test_gapBackfillEntropyUnique_fuzz(2);
        vm.revertToState(snap);
        test_gapBackfillEntropyUnique_fuzz(type(uint256).max);
    }

    /// @notice Fuzz: gap backfill entropy produces unique per-day words derived from
    ///         keccak256(vrfWord, gapDay). Verifies all gap day words are distinct.
    function test_gapBackfillEntropyUnique_fuzz(uint256 vrfWord) public {
        // The callback delivers a zero word as 1; the backfill derives from the delivered word.
        vm.assume(vrfWord > 1);
        uint256 delivered = vrfWord;

        // Complete the first post-deploy day normally
        _completeDay(0xDEAD0001);

        // Warp to the next day (day 3 absolute), trigger VRF request (will stall)
        vm.warp(3 * 86400);
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 3 VRF pending");

        // Stall for 5 gap days: warp to day 8 (absolute ts), swap coordinator
        vm.warp(8 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // The stalled request's late word finishes day 3, the day it was sent for.
        // rngWordForDay retains only today and yesterday (c729ecfc9) and the wall day is 8, so
        // read day 3's exact-tag ring entry before the wall day's request replaces it.
        _resumeAfterSwap(newVRF, 0xDEAD0003);
        assertEq(RecyclingState.dailyWord(address(game), 3), 0xDEAD0003, "Stalled day finishes on its own word");
        uint256 stalledWord = RecyclingState.dailyWord(address(game), 3);

        // Day 8's fresh request, answered with the fuzzed word, derives the final gap day.
        _catchUp(newVRF, vrfWord);

        // _backfillGapDays retains only the final gap day's derived word in the two-day ring
        // (6d0e64b09/c729ecfc9); the earlier gap days keep no word and settle through their
        // coinflip days. The day is packed as uint24 (3-byte preimage width).
        uint256 expected = uint256(keccak256(abi.encodePacked(delivered, uint24(7))));
        if (expected == 0) expected = 1;
        uint256 gapWord = game.rngWordForDay(7);
        assertEq(gapWord, expected, "Gap day word must match keccak256(vrfWord, day)");
        for (uint32 d = 4; d <= 6; d++) {
            assertEq(game.rngWordForDay(uint24(d)), 0, "earlier gap days keep no word in the two-day ring");
            (uint16 reward,) = coinflip.getCoinflipDayResult(uint24(d));
            assertTrue(reward != 0, "every gap day still settles its coinflip");
        }

        assertTrue(game.rngWordForDay(8) > 1, "wall day word never reads as the request sentinel");

        // The derived gap entropy is distinct from both delivered words around it.
        assertTrue(gapWord != game.rngWordForDay(8), "gap word distinct from the wall day's word");
        assertTrue(gapWord != stalledWord, "gap word distinct from the stalled day's word");
    }

    /// @notice Unit: verifies zero guard -- all derived gap day words are nonzero.
    function test_gapBackfillZeroGuard() public {
        // Complete the first post-deploy day normally
        _completeDay(0xDEAD0001);

        // Warp to the next day (day 3 absolute), trigger VRF request (will stall)
        vm.warp(3 * 86400);
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 3 VRF pending");

        // Stall 10 gap days: warp to day 13 (absolute), swap coordinator
        vm.warp(13 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        uint256 resumeWord = 0xBEEF0001;
        _resumeAfterSwap(newVRF, resumeWord);
        // Exact-tag ring read: the public view keeps only today/yesterday (c729ecfc9).
        assertTrue(RecyclingState.dailyWord(address(game), 3) != 0, "Stalled day 3 finished on a nonzero word");
        _catchUp(newVRF, 0xBEEF0002);

        // Zero guard on the derived word (derivedWord==0 -> 1). Only the final gap day (12) is
        // retained in the two-day ring (6d0e64b09/c729ecfc9); every gap day settles its coinflip.
        assertTrue(game.rngWordForDay(12) != 0, "Zero guard: gap day word must be nonzero");
        for (uint32 d = 4; d <= 12; d++) {
            (uint16 reward,) = coinflip.getCoinflipDayResult(uint24(d));
            assertTrue(reward != 0, "every gap day settles its coinflip");
        }
    }

    /// @notice Unit: exactly 1 gap day backfilled with correct keccak256 derivation.
    function test_gapBackfillSingleDayGap() public {
        // Complete the first post-deploy day normally
        _completeDay(0xDEAD0001);

        // Warp to the next day (day 3 absolute), trigger VRF request (will stall)
        vm.warp(3 * 86400);
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 3 VRF pending");

        // Stall into day 5, swap coordinator: day 3 finishes on its late word, day 4 is the gap
        vm.warp(5 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        _resumeAfterSwap(newVRF, 0xCAFE0000);
        uint256 resumeWord = 0xCAFE0001;
        _catchUp(newVRF, resumeWord);

        // Gap day 4 is derived from day 5's word. _backfillGapDays packs the gap day as uint24
        // (its loop counter type), so the preimage day width is 3 bytes, not 4.
        uint256 expected = uint256(keccak256(abi.encodePacked(resumeWord, uint24(4))));
        if (expected == 0) expected = 1;
        assertEq(game.rngWordForDay(4), expected, "Single gap day backfill matches keccak256");

        // Day 5 (current day) should be processed normally (not a gap day)
        assertTrue(game.rngWordForDay(5) != 0, "Current day 5 processed");
    }

    // ══════════════════════════════════════════════════════════════════════
    // STALL-02: Manipulation Window (VRF callback -> mineFlip consumption)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Unit: VRF word is stored via rawFulfillRandomWords and consumed on next
    ///         mineFlip. Both daily and gap backfill paths use the same rngWordCurrent
    ///         storage. After VRF callback, rngWordCurrent is nonzero. After processing,
    ///         rngWordCurrent is cleared. This proves the manipulation window is identical
    ///         to standard daily VRF -- no additional attack surface from gap backfill.
    function test_manipulationWindowIdenticalToDaily() public {
        // Complete the first post-deploy day normally
        _completeDay(0xDEAD0001);

        // Warp to the next day (day 3 absolute), trigger VRF request (will stall)
        vm.warp(3 * 86400);
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 3 VRF pending");

        // Stall 3 gap days: warp to day 6, swap coordinator. The daily request in flight
        // (rngWordCurrent==0) is re-issued on the new coordinator by the swap.
        vm.warp(6 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // The re-issued request already exists on the new coordinator
        uint256 reqId = newVRF.lastRequestId();
        assertTrue(reqId != 0, "Re-issued request exists on new coordinator after swap");

        // Before fulfillment: rngWordCurrent == 0
        assertEq(_readRngWordCurrent(), 0, "rngWordCurrent 0 before VRF callback");

        // VRF callback: stores word to rngWordCurrent
        uint256 resumeWord = 0xCAFEBABE;
        newVRF.fulfillRandomWords(reqId, resumeWord);

        // After callback: rngWordCurrent is nonzero (this is the manipulation window)
        assertEq(_readRngWordCurrent(), resumeWord, "rngWordCurrent set after VRF callback");

        // mineFlip consumes the word: it finishes the stalled day 3 it was requested for. The
        // engine then commits the wall day's fresh request in the same flow.
        uint48 sealedBefore = _readDailyIdx();
        for (uint256 i = 0; i < 50 && _readDailyIdx() == sealedBefore; i++) {
            if (!_step()) break;
        }
        assertEq(_readDailyIdx(), 3, "the delivered word sealed its own stalled day");

        // After processing: the session word is replaced by the wall day's fresh request (its
        // waiting sentinel reads as 0); the stalled word is never carried into day 6.
        assertTrue(game.rngLocked(), "the wall day's own request is in flight");
        assertGt(newVRF.lastRequestId(), reqId, "a fresh request, not the stalled one");
        assertEq(_readRngWordCurrent(), 0, "rngWordCurrent cleared after processing");
    }

    /// @notice Unit: coinflip bets placed before stall are resolved by gap backfill.
    ///         Players cannot add bets for past gap days (no function accepts past day).
    function test_gapDayPositionsPreCommitted() public {
        address buyer = makeAddr("flipBuyer");
        vm.deal(buyer, 100 ether);

        // Purchase 5 tickets before any day completes
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(buyer);
            game.purchase{value: 0.01 ether}(buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        }

        // Complete the first post-deploy day normally
        _completeDay(0xF11F0001);

        // Warp to the next day (day 3 absolute), trigger VRF request (will stall)
        vm.warp(3 * 86400);
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 3 VRF pending");

        // Stall + swap: warp to day 6
        vm.warp(6 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Resume: day 3 settles on its late word, day 6's word derives gap days 4 and 5
        _resumeAfterSwap(newVRF, 0xF11FCAFE);
        _catchUp(newVRF, 0xF11FCAFF);

        // Days 3,4,5 settled -> coinflip.processCoinflipPayouts
        // Verify coinflip results populated for gap days (rewardPercent >= 50)
        (uint16 reward3,) = coinflip.getCoinflipDayResult(3);
        (uint16 reward4,) = coinflip.getCoinflipDayResult(4);
        (uint16 reward5,) = coinflip.getCoinflipDayResult(5);

        assertTrue(reward3 != 0, "Stalled day 3 coinflip resolved on its late word");
        assertTrue(reward4 != 0, "Gap day 4 coinflip resolved after backfill");
        assertTrue(reward5 != 0, "Gap day 5 coinflip resolved after backfill");
    }

    // ══════════════════════════════════════════════════════════════════════
    // STALL-03: Gas Ceiling for Gap Backfill
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Gas profile: the widest live gap. A VRF stall that long is dead (14 days), so the
    ///         widest gap a live game can derive is an unattended stretch just short of the
    ///         30-day deadman: 29 skipped days, all derived in the transaction that applies the
    ///         wall day's word.
    function test_gapBackfillGasWidestLiveGap() public {
        // Complete the first post-deploy day normally (dailyIdx = 2)
        _completeDay(0xDEAD0001);

        // Nobody advances until day 32: one more day and the deadman ends the game
        vm.warp(32 * 86400);
        assertFalse(game.livenessTriggered(), "inside the deadman window");
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 32 requested");
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xAA300001);

        // Owner rule: no bound on a whole mineFlip transaction; the per-chunk cost matters.
        // Bring the engine to the gap chunk (publication and the ticket certificate first). A
        // An allowance of DAILY_GAP plus the engine reserves can never admit DAILY_GAP plus its
        // check reserve, so these calls stop before it.
        for (uint256 i; i < 8 && game.nextMinerAction() != ACTION_DAILY_GAP; ++i) {
            game.mineFlip{gas: GasBounds.DAILY_GAP + GasBounds.ENGINE_BOUNDARY + GasBounds.ENGINE_RETURN}();
        }
        assertEq(game.nextMinerAction(), ACTION_DAILY_GAP, "next chunk is the 29-day gap");

        // (a) A realistic allowance succeeds and progresses through the gap.
        uint256 snap = vm.snapshotState();
        game.mineFlip{gas: 10_000_000}();
        assertTrue(game.rngWordForDay(31) != 0, "a 10M call derives the skipped days");
        vm.revertToState(snap);

        // (b) The gap chunk alone, offered just its declared admission bound plus the engine
        // boundary/return reserves: it must fit there, and stay under the 10M chunk ceiling.
        uint256 supplied = GasBounds.DAILY_GAP + GasBounds.ENGINE_BOUNDARY + GasBounds.ENGINE_RETURN + 200_000;
        uint256 gasBefore = gasleft();
        game.mineFlip{gas: supplied}();
        uint256 gasUsed = gasBefore - gasleft();
        assertEq(game.nextMinerAction(), ACTION_DAILY_APPLY, "exactly the gap chunk ran");
        assertTrue(game.rngWordForDay(31) != 0, "every skipped day derived in that chunk");
        emit log_named_uint("29-day gap chunk: mineFlip gas (engine overhead included)", gasUsed);
        emit log_named_uint("29-day gap chunk: declared DAILY_GAP bound", GasBounds.DAILY_GAP);
        assertLt(gasUsed, 10_000_000, "29-day gap chunk stays under the 10M per-chunk ceiling");
        assertLe(gasUsed, GasBounds.DAILY_GAP + GasBounds.ENGINE_BOUNDARY + GasBounds.ENGINE_RETURN,
            "cold widest gap chunk exceeds its declared bound plus engine reserves");
    }

    // ══════════════════════════════════════════════════════════════════════
    // STALL-04: Coordinator Swap State Cleanup
    // ══════════════════════════════════════════════════════════════════════

    /// @dev Storage slot for totalFlipReversals (verified via forge inspect).
    uint256 constant SLOT_TOTAL_FLIP_REVERSALS = 5;
    /// @dev Storage slot for lootboxRngPacked (post V62 lootbox repack: was 36).
    uint256 constant SLOT_LOOTBOX_RNG_PACKED = 33;

    /// @notice Unit: coordinator swap with a daily request in flight preserves the RNG lock
    ///         and re-issues the request on the new coordinator; intentionally-kept variables
    ///         (lootboxRngIndex, historical rngWordByDay) are preserved; the day completes
    ///         once the re-issued request is fulfilled.
    function test_coordinatorSwapResetsAllVrfState() public {
        // Complete the first post-deploy day normally
        _completeDay(0xDEAD0001);

        uint256 preSwapFirstDayWord = game.rngWordForDay(2);

        // Warp to the next day (day 3 absolute), trigger VRF request -> rngLocked=true, vrfRequestId!=0, rngRequestTime!=0
        vm.warp(3 * 86400);
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 2 VRF pending");
        uint256 preSwapVrfRequestId = _readVrfRequestId();
        assertTrue(preSwapVrfRequestId != 0, "vrfRequestId set");
        uint48 preSwapStamp = _readRngRequestTime();
        assertTrue(preSwapStamp != 0, "rngRequestTime set");
        // rngWordCurrent == 0 (not yet fulfilled)
        assertEq(_readRngWordCurrent(), 0, "rngWordCurrent 0 before fulfillment");

        // Record lootboxRngIndex AFTER VRF request (mineFlip increments it)
        uint48 preSwapLootboxIndex = _lootboxRngIndex();

        // Coordinator swap (daily in flight, rngWordCurrent==0 -> preserve+re-issue)
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Verify PRESERVE+RE-ISSUE variables:
        assertTrue(game.rngLocked(), "rngLocked stays true across swap (daily preserved)");
        assertTrue(_readVrfRequestId() != 0, "vrfRequestId re-issued (fresh) on new coordinator");
        assertEq(_readRngRequestTime(), preSwapStamp, "the same request re-sent: stamp kept");
        assertTrue(_readRetrySpent(), "the re-send spends the retry");
        assertEq(_readRngWordCurrent(), 0, "rngWordCurrent still 0 (re-issued word not yet delivered)");
        // A fresh request exists on the new coordinator
        assertTrue(newVRF.lastRequestId() != 0, "re-issued request exists on new coordinator");

        // Verify PRESERVED variables:
        assertEq(
            _lootboxRngIndex(),
            preSwapLootboxIndex,
            "lootboxRngIndex preserved across swap"
        );
        assertEq(
            game.rngWordForDay(2),
            preSwapFirstDayWord,
            "Historical rngWordByDay preserved across swap"
        );

        // Liveness: fulfilling the re-issued request on the new coordinator completes the day.
        _resumeAfterSwap(newVRF, 0xCAFE0003);
        assertFalse(game.rngLocked(), "Day completes after re-issued request fulfilled");
        assertTrue(game.rngWordForDay(3) != 0, "Day 3 processed after re-issue resume");
    }

    /// @notice Fuzz: totalFlipReversals preserved across coordinator swap.
    function test_coordinatorSwapPreservesTotalFlipReversals_fuzz(uint8 nudges) public {
        // Bound to 0-3 nudges (reverseFlip costs FLIP, which must be minted via purchases)
        nudges = uint8(bound(nudges, 0, 3));

        // Day 1: complete normally (to get FLIP minted for nudge purchases)
        address buyer = makeAddr("nudgeBuyer");
        vm.deal(buyer, 100 ether);

        // Purchase enough to mint FLIP for nudges
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(buyer);
            game.purchase{value: 0.5 ether}(buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        }
        _completeDay(0xDEAD0001);

        // Apply nudges (reverseFlip increments totalFlipReversals)
        for (uint8 n = 0; n < nudges; n++) {
            (, uint256 cost) = game.rngNudgeQuote();
            vm.prank(buyer);
            try game.reverseFlip(cost) {} catch {
                break; // Not enough FLIP or RNG locked
            }
        }

        // Record totalFlipReversals before swap
        uint256 preSwapReversals = uint256(
            RecyclingState.nudgeCount(address(game))
        );

        // Warp to the next day (day 3 absolute), trigger VRF request, then swap
        vm.warp(3 * 86400);
        game.mineFlip();
        _doCoordinatorSwap();

        // totalFlipReversals must be preserved
        uint256 postSwapReversals = uint256(
            RecyclingState.nudgeCount(address(game))
        );
        assertEq(
            postSwapReversals,
            preSwapReversals,
            "_nudgeCount() preserved across swap"
        );
    }

    /// @notice Unit: midDayTicketRngPending preserved across coordinator swap; the mid-day
    ///         request is re-issued on the new coordinator for the same reserved index, and
    ///         fulfilling it lands the genuine word in that index without orphaning it.
    function test_coordinatorSwapClearsMidDayPending() public {
        // Complete the first post-deploy day normally
        _completeDay(0xDEAD0001);

        // Warp to the next day (day 3 absolute), complete it so we have a daily word for mid-day request
        vm.warp(3 * 86400);
        _completeDay(0xDEAD0002);

        // Setup for mid-day: purchase with lootbox amount
        address buyer = makeAddr("midDayBuyer");
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: 1.01 ether}(buyer, 400, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);

        // Fund VRF subscription
        mockVRF.fundSubscription(1, 100e18);

        // Request mid-day lootbox RNG
        game.requestLootboxRng();

        // The reserved index this mid-day request is bound to (LR_INDEX - 1)
        uint48 reservedIndex = (_lootboxRngIndex() ^ 1);

        // Verify midDayTicketRngPending is set (bits 224-231 of lootboxRngPacked slot 36)
        uint256 lrPacked = uint256(
            vm.load(address(game), bytes32(uint256(SLOT_LOOTBOX_RNG_PACKED)))
        );
        uint256 midDayVal = (lrPacked >> 224) & 0xFF;
        assertTrue(midDayVal != 0, "midDayTicketRngPending should be set after requestLootboxRng");

        // Coordinator swap (mid-day in flight -> preserve LR_MID_DAY + re-issue for the same index)
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Verify midDayTicketRngPending PRESERVED (bits 224-231 of lootboxRngPacked slot 36)
        lrPacked = uint256(
            vm.load(address(game), bytes32(uint256(SLOT_LOOTBOX_RNG_PACKED)))
        );
        midDayVal = (lrPacked >> 224) & 0xFF;
        assertEq(midDayVal, 1, "midDayTicketRngPending preserved after swap (re-issued)");

        // LR_INDEX preserved -> the re-issue targets the same reserved index
        assertEq((_lootboxRngIndex() ^ 1), reservedIndex, "reserved lootbox index preserved across swap");

        // A re-issued request exists on the new coordinator
        uint256 reissued = newVRF.lastRequestId();
        assertTrue(reissued != 0, "mid-day request re-issued on new coordinator");

        // Fulfil the re-issued mid-day request on the new coordinator -> word lands in [reservedIndex].
        // The callback only stores the word; publication is the keeper's first action.
        newVRF.fulfillRandomWords(reissued, 0xDD030001);
        game.mineFlip();
        assertEq(
            _lootboxRngWord(reservedIndex),
            0xDD030001,
            "Re-issued mid-day word lands in the reserved index (not orphaned)"
        );

        // Mid-day publication retires the in-flight request authority (slot-0 request-active
        // bit). The physical id and stamp are retained as history by design (60d31f775), so the
        // logical state is what clears; no request is live.
        assertEq((uint256(vm.load(address(game), bytes32(uint256(SLOT_PACKED_0)))) >> 254) & 1, 0,
            "vrfRequestId authority cleared after mid-day fulfillment");
        assertFalse(game.isRngFulfilled(), "no live request remains after mid-day publication");

        // Game proceeds without NotTimeYet: advance into the next day
        vm.warp(4 * 86400);
        game.mineFlip();
    }

    /// @notice Unit: a mid-day lootbox RNG request that stalls across midnight is no longer
    ///         promoted into the next daily request (that RNGREUSE path was removed in
    ///         60d31f775/6d0e64b09). It BLOCKS the next daily request until it lands: the
    ///         daily advance waits (RngNotReady), the Admin retry re-sends it for the same
    ///         reserved bucket (no index advance, the late original is rejected), its word
    ///         finalizes the reserved bucket and drains the swapped ticket batch, and only then
    ///         does the day's fresh daily request go out — no deadlock.
    function test_stalledMidDayBlocksDailyUntilRetryLands() public {
        // Complete day 2 so a daily word exists for the mid-day request gate
        _completeDay(0xDEAD0001);
        vm.warp(3 * 86400);
        _completeDay(0xDEAD0002);

        // Purchase enough to push pending ETH past threshold AND populate the
        // write-slot ticket queue (so requestLootboxRng commits the swap)
        address buyer = makeAddr("midDayBuyer");
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: 1.01 ether}(buyer, 400, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);

        mockVRF.fundSubscription(1, 100e18);

        // Snapshot pre-request state
        uint48 preIndex = _lootboxRngIndex();

        // Fire the mid-day request
        game.requestLootboxRng();

        uint256 stalledReqId = mockVRF.lastRequestId();
        uint48 postRequestIndex = _lootboxRngIndex();
        uint48 reservedBucket = (postRequestIndex ^ 1);

        assertTrue(stalledReqId != 0, "Mid-day VRF request fired");
        assertEq(postRequestIndex, (preIndex ^ 1), "Mid-day request advanced lootboxRngIndex");
        assertFalse(game.rngLocked(), "Mid-day request leaves the daily lock clear");

        // Confirm LR_MID_DAY = 1 (swap committed)
        uint256 lrPacked = uint256(
            vm.load(address(game), bytes32(uint256(SLOT_LOOTBOX_RNG_PACKED)))
        );
        assertTrue(((lrPacked >> 224) & 0xFF) != 0, "LR_MID_DAY set after mid-day request");

        // The mid-day VRF stalls across midnight: the next day's advance waits on it.
        vm.warp(4 * 86400);
        vm.expectRevert(RNG_NOT_READY);
        game.mineFlip();
        assertEq(mockVRF.lastRequestId(), stalledReqId, "no daily request while the mid-day word is outstanding");
        assertFalse(game.rngLocked(), "the daily lock is not taken over the stalled mid-day request");

        // The vault owner's single Admin retry (20h after the stamp) re-sends the same request.
        vm.prank(ContractAddresses.CREATOR);
        admin.retryGameRng();
        uint256 retryReqId = mockVRF.lastRequestId();
        assertTrue(retryReqId != stalledReqId, "the retry issued a replacement VRF request");
        assertFalse(game.rngLocked(), "the retry preserves the mid-day mode");
        assertEq(
            _lootboxRngIndex(),
            postRequestIndex,
            "Retry preserves lootboxRngIndex (no double-advance)"
        );

        // The abandoned mid-day request is auto-rejected on late arrival (requestId mismatch).
        mockVRF.fulfillRandomWords(stalledReqId, 0x1111);
        assertEq(_readRngWordCurrent(), 0, "Stalled mid-day word rejected on id mismatch");

        // The replacement word finalizes the reserved bucket; the swapped batch drains and the
        // day's fresh daily request follows.
        mockVRF.fulfillRandomWords(retryReqId, 0xCAFE0BAD);
        vm.recordLogs();
        game.mineFlip();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool applied;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == keccak256("LootboxRngApplied(uint48,uint256,uint256)")) {
                (uint48 index, uint256 word, uint256 requestId) = abi.decode(logs[i].data, (uint48, uint256, uint256));
                if (index == reservedBucket && word == 0xCAFE0BAD && requestId == retryReqId) applied = true;
            }
        }
        assertTrue(applied, "The retried word finalized the reserved mid-day bucket");

        // Daily flow completes after the recovery (no deadlock).
        for (uint256 i = 0; i < 50; i++) {
            uint256 id = mockVRF.lastRequestId();
            (,, bool done) = mockVRF.pendingRequests(id);
            if (!done) mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode("day4", id))));
            if (!game.rngLocked() && _readDailyIdx() == 4) break;
            _step();
        }
        assertFalse(game.rngLocked(), "Daily flow completes after the mid-day recovery (no deadlock)");
        assertEq(_readDailyIdx(), 4, "day 4 sealed on its own daily word");
    }

    // ══════════════════════════════════════════════════════════════════════
    // STALL-05: Zero-Seed Edge Case
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Unit: after day 1 completes, lootboxRngWord at current index is nonzero.
    ///         Coordinator swap preserves it. Resume updates it to new value.
    function test_zeroSeedUnreachableAfterSwap() public {
        // Complete the first post-deploy day normally
        _completeDay(0xDEAD0001);

        // Verify lootboxRngWord at current index is nonzero after completing the first day
        uint48 firstDayIndex = (_lootboxRngIndex() ^ 1);
        assertTrue(_lootboxRngWord(firstDayIndex) != 0, "lootboxRngWord at current index nonzero after first day");

        // Warp to the next day (day 3 absolute), trigger VRF request, then swap. The fresh
        // request seals the other physical buffer and retires the first day's session (two
        // physical buffers, 6d0e64b09), so the swap is judged against the post-request state.
        vm.warp(3 * 86400);
        game.mineFlip();
        uint48 preSwapIndex = (_lootboxRngIndex() ^ 1);
        assertEq(preSwapIndex, firstDayIndex ^ 1, "the request sealed the other buffer");
        uint256 preSwapWord = _lootboxRngWord(preSwapIndex);
        uint256 preSwapCurrent = _readRngWordCurrent();
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Verify the swap leaves the sealed buffer and its (not yet delivered) word untouched
        assertEq(_lootboxRngIndex() ^ 1, preSwapIndex, "the swap keeps the sealed buffer");
        uint256 postSwapWord = _lootboxRngWord(preSwapIndex);
        assertEq(postSwapWord, preSwapWord, "lootboxRngWord at current index preserved by swap");
        assertEq(_readRngWordCurrent(), preSwapCurrent, "the swap installs no word of its own");

        // Resume with new VRF
        _resumeAfterSwap(newVRF, 0xCAFE0002);

        // After resume: lootboxRngWord at new index updated via _finalizeLootboxRng
        uint48 postResumeIndex = (_lootboxRngIndex() ^ 1);
        uint256 postResumeWord = _lootboxRngWord(postResumeIndex);
        assertTrue(postResumeWord != 0, "lootboxRngWord at current index nonzero after resume");
    }

    /// @notice Unit: at game start (before any day completion), lootboxRngWord at index 0 == 0.
    ///         After coordinator swap at start + resume cycle, the resume index becomes nonzero.
    function test_zeroSeedAtGameStart() public {
        // At game start: lootboxRngWord at index 0 should be 0 (no day completed yet)
        assertEq(_lootboxRngWord(0), 0, "No word at index 0 at game start");

        // Trigger VRF request (day 1) -- increments lootboxRngIndex from 1 to 2
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 1 VRF request pending");

        // Coordinator swap at game start (edge case): the daily request is re-sent for the
        // same reserved index
        uint48 reservedIndex = (_lootboxRngIndex() ^ 1);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();
        assertEq((_lootboxRngIndex() ^ 1), reservedIndex, "swap re-sends for the reserved index");
        assertEq(_lootboxRngWord(reservedIndex), 0, "reserved index unfinalized before the word");

        // Resume: the re-sent request's word finalizes that index
        _resumeAfterSwap(newVRF, 0xF0E50001);
        assertTrue(
            _lootboxRngWord(reservedIndex) != 0,
            "Lootbox word at resume index nonzero after resume from start"
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    // STALL-06: Swap Re-issue + V37-001 Guard Branches
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Unit: after coordinator swap with a daily request in flight, the swap
    ///         re-issues the request on the new valid coordinator and preserves rngLocked.
    ///         This proves the re-issue path uses the new coordinator's valid VRF config
    ///         (address, keyHash, subId) — the request is accepted, not orphaned.
    function test_tryRequestRngGuardBranches() public {
        // Complete the first post-deploy day normally
        _completeDay(0xDEAD0001);

        // Warp to the next day (day 3 absolute), trigger VRF request (will stall)
        vm.warp(3 * 86400);
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 3 VRF pending");

        // Coordinator swap to a valid new coordinator (daily in flight -> preserve+re-issue)
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // After swap: rngLocked preserved, the request is re-issued on the new coordinator
        assertTrue(game.rngLocked(), "rngLocked preserved after swap (re-issued)");

        // The new coordinator received the re-issued VRF request
        uint256 reqId = newVRF.lastRequestId();
        assertTrue(reqId > 0, "New coordinator received re-issued VRF request");

        // Fulfilling the re-issued request on the new coordinator drains the day
        _resumeAfterSwap(newVRF, 0xDD0B0003);
        assertFalse(game.rngLocked(), "Day completes after re-issued request fulfilled");
    }

    // ══════════════════════════════════════════════════════════════════════
    // STALL-07: DailyIdx Timing Consistency
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Unit: flipDay = day + 1 alignment. After day 1 completes,
    ///         getCoinflipDayResult(2) has nonzero rewardPercent (flipDay=1+1=2).
    function test_flipDayAlignedWithDailyIdx() public {
        // Purchase tickets so the first post-deploy day processCoinflipPayouts has something to write
        address buyer = makeAddr("alignBuyer");
        vm.deal(buyer, 100 ether);
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(buyer);
            game.purchase{value: 0.01 ether}(buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        }

        // Complete the first post-deploy day (day 2) normally
        _completeDay(0xA1160001);

        // Verify rngWordForDay(2) is nonzero (day 2 was processed)
        assertTrue(game.rngWordForDay(2) != 0, "Day 2 has RNG word");

        // The coinflip result for day 2 should be set by day 2 processing.
        // processCoinflipPayouts(word, day=2) writes coinflipDayResult[2]
        (uint16 reward,) = coinflip.getCoinflipDayResult(2);
        assertTrue(reward != 0, "Day 2 coinflip result populated (processCoinflipPayouts writes to day param)");
    }

    /// @notice Unit: gap days get coinflip processing, game advances past the gap.
    function test_gapDaysSkipResolveRedemptionPeriod() public {
        // Complete the first post-deploy day normally
        _completeDay(0xDEAD0001);

        // Warp to the next day (day 3 absolute), trigger VRF request (will stall)
        vm.warp(3 * 86400);
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 3 VRF pending");

        // Stall 3 gap days: warp to day 6
        vm.warp(6 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Resume: the stalled request finishes day 3 on its late word
        _resumeAfterSwap(newVRF, 0xBACF0001);
        // Exact-tag ring read: the public view keeps only today/yesterday (c729ecfc9).
        assertTrue(RecyclingState.dailyWord(address(game), 3) != 0, "Stalled day 3 finished");
        assertEq(_readDailyIdx(), 3, "sealed through the stalled day");

        // Day 6's fresh request settles gap days 4 and 5 and completes day 6. Only the final
        // gap day keeps a derived word in the two-day ring (6d0e64b09/c729ecfc9).
        _catchUp(newVRF, 0xBACF0002);
        (uint16 reward4,) = coinflip.getCoinflipDayResult(4);
        assertTrue(reward4 != 0, "Gap day 4 backfilled");
        assertEq(game.rngWordForDay(4), 0, "earlier gap day keeps no word");
        assertTrue(game.rngWordForDay(5) != 0, "Gap day 5 backfilled");
        assertTrue(game.rngWordForDay(6) != 0, "Current day 6 processed");

        // Skipped days are never re-walked: dailyIdx jumps past the gap to the wall day.
        assertEq(_readDailyIdx(), 6, "dailyIdx reaches the current day");
    }

    /// @notice Unit: wall-clock day advances during stall but dailyIdx does not.
    function test_wallClockDayAdvancesDuringStall() public {
        // Complete the first post-deploy day normally
        _completeDay(0xDEAD0001);

        // Record currentDayView and dailyIdx after completing the first post-deploy day
        uint48 dayAfterComplete = game.currentDayView();
        uint48 idxAfterComplete = _readDailyIdx();
        assertEq(idxAfterComplete, 2, "dailyIdx == 2 after first post-deploy day complete");

        // Warp +3 days without advancing (stall scenario without VRF request)
        vm.warp(5 * 86400);

        // currentDayView (wall-clock) has advanced
        uint48 wallClockDay = game.currentDayView();
        assertTrue(wallClockDay > dayAfterComplete, "Wall-clock day advanced during stall");

        // dailyIdx has NOT advanced (still at 2, no mineFlip called)
        uint48 stallIdx = _readDailyIdx();
        assertEq(stallIdx, idxAfterComplete, "dailyIdx frozen during stall");

        // rngWordForDay(3) == 0 (day 3 never processed during stall)
        assertEq(game.rngWordForDay(3), 0, "Day 3 never processed during stall");

        // rngWordForDay(4) == 0 (day 4 never processed during stall)
        assertEq(game.rngWordForDay(4), 0, "Day 4 never processed during stall");
    }
}
