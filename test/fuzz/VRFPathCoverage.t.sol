// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title VRFPathCoverage -- Parametric fuzz tests for gap backfill edge cases (TEST-03)
/// @notice Complements the invariant tests from VRFPathInvariants by testing specific
///         boundary scenarios with fuzzed VRF words: single-day gap, multi-day gap,
///         the widest live gap (29 skipped days, one short of the 30-day deadman), mid-day
///         pending state, entropy uniqueness, and index lifecycle across stall recovery.
///
/// @dev A stalled request keeps the day it was sent for: its late word finishes that day, and
///      the wall day's fresh request derives every skipped day in between as
///      keccak256(abi.encodePacked(word, uint24(day))). The stalled day's word is fixed here;
///      the fuzzed word is the wall day's, the one every gap day derives from.
contract VRFPathCoverage is DeployProtocol {

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    /// @dev Complete a full day: mineFlip -> VRF fulfill -> loop until unlocked.
    function _completeDay(uint256 vrfWord) internal {
        _finishReadConsumers();
        game.mineFlip();
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, vrfWord);
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.mineFlip();
        }
            _finishReadConsumers();
    }

    /// @dev Read lootboxRngIndex from lootboxRngPacked (storage slot 33, low 48 bits = LR_INDEX).
    function _lootboxRngIndex() internal view returns (uint48) {
        return RecyclingState.writeBuffer(address(game));
    }

    /// @dev Read _lootboxWord(index) from storage (mapping at slot 34).
    function _lootboxRngWord(uint48 index) internal view returns (uint256) {
        return RecyclingState.word(address(game), index);
    }

    /// @dev Read dailyIdx from packed slot 0 (uint24 at bit offset 24).
    function _readDailyIdx() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(0))) >> 24);
    }

    /// @dev The word _backfillGapDays derives for a skipped day. The day is packed as uint24
    ///      (its loop counter type), so the preimage day width is 3 bytes.
    function _derived(uint256 word, uint256 day) internal pure returns (uint256 w) {
        w = uint256(keccak256(abi.encodePacked(word, uint24(day))));
        if (w == 0) w = 1;
    }

    /// @dev Deploy a new MockVRFCoordinator and wire it up via admin prank.
    function _doCoordinatorSwap() internal returns (MockVRFCoordinator newVRF) {
        newVRF = new MockVRFCoordinator();
        uint256 newSubId = newVRF.createSubscription();
        newVRF.addConsumer(newSubId, address(game));
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(newVRF), newSubId, bytes32(uint256(1)));
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
    ///      new coordinator, so a pending request already exists: fulfil it, then drain. A
    ///      stalled daily request's word finishes the day it was sent for; the composed call
    ///      that seals it goes straight on to the wall day's fresh request, so a daily resume
    ///      stops on the seal. A mid-day resume stops once its word is published. If nothing
    ///      was in flight, mineFlip fires a fresh request first.
    function _resumeAfterSwap(MockVRFCoordinator newVRF, uint256 vrfWord) internal {
        uint256 reqId = newVRF.lastRequestId();
        if (reqId == 0) {
            game.mineFlip();
            reqId = newVRF.lastRequestId();
        }
        bool daily = game.rngLocked();
        uint24 sealedBefore = _readDailyIdx();
        newVRF.fulfillRandomWords(reqId, vrfWord);
        for (uint256 i = 0; i < 500; i++) {
            if (daily ? _readDailyIdx() > sealedBefore : !game.isRngFulfilled()) break;
            if (!_step()) break;
        }
    }

    /// @dev Catch up after the stalled day finished: the wall day's fresh request is answered
    ///      with `word`, which derives the final skipped day's word, and the wall day completes.
    function _catchUp(MockVRFCoordinator vrf, uint256 word) internal {
        uint24 wallDay = game.currentDayView();
        _finishReadConsumers();
        for (uint256 i = 0; i < 500; i++) {
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

    /// @dev Stall the day-3 request, swap coordinators at `resumeDay` and finish day 3 on the
    ///      re-issued request's late word. `resumeDay` stays under 14 days from the send, so
    ///      the request is answered while VRF still counts as alive.
    function _stallDay3AndResume(uint256 resumeDay) internal returns (MockVRFCoordinator newVRF) {
        _completeDay(0xDEAD0001);
        vm.warp(3 * 86400);
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 3 VRF pending");

        vm.warp(resumeDay * 86400);
        newVRF = _doCoordinatorSwap();
        _resumeAfterSwap(newVRF, 0xDEAD0003);
        // rngWordForDay retains only today and yesterday (c729ecfc9); the wall day is later,
        // so read day 3's exact-tag ring entry before the wall day's request replaces it.
        assertEq(RecyclingState.dailyWord(address(game), 3), 0xDEAD0003, "Stalled day finishes on its own word");
        assertEq(_readDailyIdx(), 3, "sealed through the stalled day");
    }

    /// @dev Make a purchase for player with the given lootbox ETH amount.
    function _makePurchase(address player, uint256 lootboxAmount) internal {
        vm.deal(player, 100 ether);
        vm.prank(player);
        game.purchase{value: lootboxAmount + 0.01 ether}(
            player, 400, BoxOrderLib.boCustomFloor(lootboxAmount), bytes32(0), MintPaymentKind.DirectEth, false
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    // TEST-03a: Single-Day Gap Backfill
    // ══════════════════════════════════════════════════════════════════════

    /// @dev Delivered words 0 and 1 apply above rngGate's request-sent sentinel (1), so the
    ///      wall day still completes.
    function test_gapBackfillSingleDay_sentinelWords() public {
        uint256 snap = vm.snapshotState();
        test_gapBackfillSingleDay_fuzz(2);
        vm.revertToState(snap);
        test_gapBackfillSingleDay_fuzz(type(uint256).max);
    }

    /// @notice Fuzz: day 3 stalls into day 5. Day 3 finishes on its own late word, day 5's
    ///         fresh (fuzzed) word derives the single gap day 4.
    function test_gapBackfillSingleDay_fuzz(uint256 vrfWord) public {
        vm.assume(vrfWord > 1);
        MockVRFCoordinator newVRF = _stallDay3AndResume(5);
        _catchUp(newVRF, vrfWord);

        assertEq(game.rngWordForDay(4), _derived(vrfWord, 4), "Gap day 4 derives from day 5's word");
        assertTrue(game.rngWordForDay(5) != 0, "Current day 5 processed");
        assertEq(_readDailyIdx(), 5, "dailyIdx jumps past the gap to the wall day");
    }

    // ══════════════════════════════════════════════════════════════════════
    // TEST-03b: Multi-Day Gap Backfill (2-29 days)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Fuzz: 2-29 skipped days derived with unique nonzero words. The stalled day-3
    ///         request is answered before it is 14 days old. On a resume day before the wall
    ///         day, the composed call that seals day 3 also commits that day's own fresh
    ///         request (the engine selects it in the same flow, 60d31f775), so that day is
    ///         finished and the gap of `gapDays` skipped days runs from it; past that the game
    ///         sits unattended until the wall day, at most 30 days past the last seal.
    function test_gapBackfillMultiDay_fuzz(uint256 vrfWord, uint8 rawGapDays) public {
        vm.assume(vrfWord > 1);
        uint256 gapDays = bound(rawGapDays, 2, 29);
        uint256 wallDay = 4 + gapDays;
        uint256 resumeDay = wallDay < 16 ? wallDay : 16;

        MockVRFCoordinator newVRF = _stallDay3AndResume(resumeDay);
        uint256 lastSealed = 3;
        if (wallDay > resumeDay) {
            _catchUp(newVRF, 0xDEAD0016);
            lastSealed = _readDailyIdx();
            assertEq(lastSealed, resumeDay, "the resume day sealed on its own request");
            wallDay = lastSealed + 1 + gapDays;
        }
        vm.warp(wallDay * 86400);
        assertFalse(game.livenessTriggered(), "inside the deadman window");
        _catchUp(newVRF, vrfWord);

        // Only the final gap day keeps its derived word in the two-day ring (6d0e64b09 /
        // c729ecfc9); every gap day still settles through its coinflip day.
        uint256 w = game.rngWordForDay(uint24(wallDay - 1));
        assertEq(w, _derived(vrfWord, wallDay - 1), "Gap day word must match keccak256(word, day)");
        assertTrue(w != game.rngWordForDay(uint24(wallDay)), "Gap day words must be unique");
        for (uint256 d = lastSealed + 1; d < wallDay; d++) {
            if (d + 1 < wallDay) assertEq(game.rngWordForDay(uint24(d)), 0, "earlier gap days keep no word");
            (uint16 reward,) = coinflip.getCoinflipDayResult(uint24(d));
            assertTrue(reward != 0, "every gap day settles its coinflip");
        }
        assertEq(_readDailyIdx(), wallDay, "dailyIdx jumps past the gap to the wall day");
    }

    // ══════════════════════════════════════════════════════════════════════
    // TEST-03c: Widest Live Gap with Gas Ceiling
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Fuzz: the widest gap a live game derives, and its per-chunk gas. A request
    ///         unanswered for 14 days is VRF dead, so a stall alone never reaches it; the bound
    ///         is the deadman. Day 3 stalls 13 days and finishes on its late word; the composed
    ///         resume call on day 16 also commits day 16's own request (60d31f775), which is
    ///         finished too. Then nobody advances until day 46 (dailyIdx 16 + 30): 29 skipped
    ///         days, all derived in the one gap chunk that precedes day 46's word. One more day
    ///         trips the deadman and the game ends instead.
    function test_gapBackfillMaxGap_fuzz(uint256 vrfWord) public {
        vm.assume(vrfWord > 1);
        MockVRFCoordinator newVRF = _stallDay3AndResume(16);
        _catchUp(newVRF, 0xDEAD0016);
        assertEq(_readDailyIdx(), 16, "the resume day sealed on its own request");

        // Boundary: day 47 is 31 days past the last seal.
        uint256 snap = vm.snapshotState();
        vm.warp(47 * 86400);
        assertTrue(game.livenessTriggered(), "one day past the widest gap trips the deadman");
        vm.revertToState(snap);

        vm.warp(46 * 86400);
        assertFalse(game.livenessTriggered(), "inside the deadman window");
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 46 requested");
        newVRF.fulfillRandomWords(newVRF.lastRequestId(), vrfWord);

        // Owner rule: no bound on a whole mineFlip transaction; the per-chunk cost matters.
        // An allowance of DAILY_GAP plus the engine reserves can never admit DAILY_GAP plus its
        // check reserve: these calls stop before it.
        for (uint256 i; i < 8 && game.nextMinerAction() != ACTION_DAILY_GAP; ++i) {
            game.mineFlip{gas: GasBounds.DAILY_GAP + GasBounds.ENGINE_BOUNDARY + GasBounds.ENGINE_RETURN}();
        }
        assertEq(game.nextMinerAction(), ACTION_DAILY_GAP, "next chunk is the 29-day gap");
        // (a) a realistic allowance succeeds and progresses through the gap
        snap = vm.snapshotState();
        game.mineFlip{gas: 10_000_000}();
        assertTrue(game.rngWordForDay(45) != 0, "a 10M call derives the skipped days");
        vm.revertToState(snap);
        // (b) the gap chunk alone, at its declared admission bound plus the engine reserves
        uint256 supplied = GasBounds.DAILY_GAP + GasBounds.ENGINE_BOUNDARY + GasBounds.ENGINE_RETURN + 200_000;
        uint256 gasBefore = gasleft();
        game.mineFlip{gas: supplied}();
        uint256 gasUsed = gasBefore - gasleft();
        assertEq(game.nextMinerAction(), ACTION_DAILY_APPLY, "exactly the gap chunk ran");
        assertTrue(game.rngWordForDay(45) != 0, "every skipped day derived in that chunk");
        emit log_named_uint("29-day gap chunk: mineFlip gas (engine overhead included)", gasUsed);
        assertLt(gasUsed, 10_000_000, "29-day gap chunk stays under the 10M per-chunk ceiling");

        _catchUp(newVRF, vrfWord);
        // The final gap day keeps its derived word; earlier ones keep none in the two-day ring
        // (6d0e64b09/c729ecfc9) and settle through their coinflip days.
        assertEq(game.rngWordForDay(45), _derived(vrfWord, 45),
            "widest survivable gap: every gap day derives from the wall day's word");
        for (uint256 d = 17; d <= 45; d++) {
            (uint16 reward,) = coinflip.getCoinflipDayResult(uint24(d));
            assertTrue(reward != 0, "widest survivable gap: every gap day settles");
        }
        assertEq(_readDailyIdx(), 46, "dailyIdx reaches the wall day");
        assertFalse(game.livenessTriggered(), "the game survives the widest gap");
    }

    // ══════════════════════════════════════════════════════════════════════
    // TEST-03d: Gap Backfill with Mid-Day Pending State
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Fuzz: a mid-day lootbox request left pending across a stall. The swap re-issues
    ///         it for its reserved index; its word fills that index but seals no day. Day 8's
    ///         fresh daily request then derives gap days 4..7.
    function test_gapBackfillWithMidDayPending_fuzz(uint256 vrfWord) public {
        vm.assume(vrfWord > 1);
        // Complete the first post-deploy day normally
        _completeDay(0xDEAD0001);

        // Warp to day 3, complete it so we have a daily word for mid-day request
        vm.warp(3 * 86400);
        _completeDay(0xDEAD0002);

        // A lootbox purchase gives the mid-day request something to resolve
        _makePurchase(makeAddr("midDayBuyer"), 1 ether);

        // Fund VRF subscription for mid-day request
        mockVRF.fundSubscription(1, 100e18);

        // Request mid-day lootbox RNG (creates mid-day pending state)
        game.requestLootboxRng();
        uint48 indexBeforeStall = _lootboxRngIndex();
        uint48 reservedIndex = (indexBeforeStall ^ 1);

        // Stall into day 8, swap: the mid-day request is re-issued for the same reserved index
        vm.warp(8 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();
        // The callback stores the word; publication is the next call's first action, and that
        // call may continue through the drained cohort into day 8's daily request.
        uint256 reissued = newVRF.lastRequestId();
        newVRF.fulfillRandomWords(reissued, 0xDEAD0004);
        vm.recordLogs();
        game.mineFlip();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool filled;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == keccak256("LootboxRngApplied(uint48,uint256,uint256)")) {
                (uint48 index, uint256 word, uint256 requestId) = abi.decode(logs[i].data, (uint48, uint256, uint256));
                if (index == reservedIndex && word == 0xDEAD0004 && requestId == reissued) filled = true;
            }
        }
        assertTrue(filled, "Re-issued mid-day word fills its reserved index");

        // Day 8's fresh request derives the final gap day; earlier gap days keep no word in
        // the two-day ring (6d0e64b09/c729ecfc9) and settle through their coinflip days.
        _catchUp(newVRF, vrfWord);
        assertEq(game.rngWordForDay(7), _derived(vrfWord, 7),
            "Gap day must derive from the wall day's word after mid-day stall recovery");
        for (uint32 d = 4; d <= 7; d++) {
            (uint16 reward,) = coinflip.getCoinflipDayResult(uint24(d));
            assertTrue(reward != 0, "every gap day settles after mid-day stall recovery");
        }

        // Two physical buffers: the mid-day seal flipped the write side once; day 8's request
        // flipped it again, so the stall's sealed buffer is the write side again.
        assertTrue(
            _lootboxRngIndex() == indexBeforeStall ^ 1,
            "lootboxRngIndex must advance after mid-day stall recovery"
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    // TEST-03e: Gap Backfill Entropy Uniqueness
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Fuzz: gap backfill produces unique per-day entropy via keccak256(word, day).
    ///         Day 3 stalls into day 13; day 13's fuzzed word derives gap days 4..12.
    function test_gapBackfillEntropyUnique_fuzz(uint256 vrfWord) public {
        vm.assume(vrfWord > 1);
        MockVRFCoordinator newVRF = _stallDay3AndResume(13);
        _catchUp(newVRF, vrfWord);

        // The final gap day's retained word (the two-day ring keeps only it, 6d0e64b09 /
        // c729ecfc9) matches the derivation and differs from both delivered words around it.
        uint256 w = game.rngWordForDay(12);
        assertEq(w, _derived(vrfWord, 12), "Gap day word must match keccak256(word, day)");
        assertTrue(w != 0xDEAD0003, "Gap words differ from the stalled day's word");
        assertTrue(w != game.rngWordForDay(13), "Gap day words must be pairwise distinct (keccak256 uniqueness)");
        for (uint32 d = 4; d <= 11; d++) {
            assertEq(game.rngWordForDay(uint24(d)), 0, "earlier gap days keep no word");
            (uint16 reward,) = coinflip.getCoinflipDayResult(uint24(d));
            assertTrue(reward != 0, "every gap day settles its coinflip");
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // TEST-03f: Index Lifecycle Across Stall Recovery
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Fuzz: lootboxRngIndex monotonically increases across stall recovery,
    ///         with no double-increments or skips. Recovery word is fuzzed.
    function test_indexLifecycleAcrossStall_fuzz(uint256 vrfWord) public {
        vm.assume(vrfWord > 1);
        // Record initial index
        uint48 initialIndex = _lootboxRngIndex();

        // Complete the first post-deploy day normally with fixed word
        _completeDay(0xDEAD0001);
        uint48 indexAfterFirstDay = _lootboxRngIndex();
        assertEq(
            indexAfterFirstDay,
            initialIndex ^ 1,
            "First day: index should increment by exactly 1"
        );

        // Warp to the next day (day 3 absolute), trigger VRF request (will stall)
        vm.warp(3 * 86400);
        game.mineFlip();
        assertTrue(game.rngLocked(), "Day 3 VRF pending");
        uint48 indexAfterDay3Request = _lootboxRngIndex();

        // Index must have increased (fresh daily request increments it)
        assertTrue(
            indexAfterDay3Request == (indexAfterFirstDay ^ 1),
            "Day 3 request: index must not decrease"
        );

        // Coordinator swap (should NOT change index)
        vm.warp(6 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();
        assertEq(
            _lootboxRngIndex(),
            indexAfterDay3Request,
            "Coordinator swap must not change lootboxRngIndex"
        );

        // Resume with fuzzed recovery word: the callback stores it and the next call publishes
        // it on the sealed buffer before anything else.
        newVRF.fulfillRandomWords(newVRF.lastRequestId(), vrfWord);
        vm.recordLogs();
        game.mineFlip();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 published;
        uint48 publishedIndex;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == keccak256("LootboxRngApplied(uint48,uint256,uint256)")) {
                (publishedIndex, published,) = abi.decode(logs[i].data, (uint48, uint256, uint256));
                break;
            }
        }
        // The recovery word lands on the buffer the day-3 request sealed (no extra flip), then
        // the stalled day seals and the wall day's fresh request flips the buffers exactly once.
        assertEq(publishedIndex, indexAfterFirstDay, "recovery publishes the current read word on the sealed buffer");
        assertEq(published, vrfWord, "recovery publishes the current read word");
        for (uint256 i = 0; i < 500 && _readDailyIdx() < 3; i++) {
            if (!_step()) break;
        }
        assertEq(_readDailyIdx(), 3, "the recovery word sealed the stalled day");
        uint48 finalIndex = _lootboxRngIndex();
        assertTrue(
            finalIndex == (game.rngLocked() ? indexAfterDay3Request ^ 1 : indexAfterDay3Request),
            "Final index must be >= index after day 3 request (monotonic)"
        );
        // A retired buffer exposes no word once a later request has sealed it.
        if (game.rngLocked()) assertEq(_lootboxRngWord(indexAfterFirstDay), 0, "retired word is unavailable");
        assertEq(_lootboxRngWord(initialIndex), 0, "retired word is unavailable");
    }
}
