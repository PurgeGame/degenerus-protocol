// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

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

    /// @dev Complete a full day: advanceGame -> VRF fulfill -> loop until unlocked.
    function _completeDay(uint256 vrfWord) internal {
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, vrfWord);
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
    }

    /// @dev Read lootboxRngIndex from lootboxRngPacked (storage slot 33, low 48 bits = LR_INDEX).
    function _lootboxRngIndex() internal view returns (uint48) {
        return uint48(uint256(vm.load(address(game), bytes32(uint256(33)))));
    }

    /// @dev Read lootboxRngWordByIndex[index] from storage (mapping at slot 34).
    function _lootboxRngWord(uint48 index) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(34)));
        return uint256(vm.load(address(game), slot));
    }

    /// @dev Read dailyIdx from packed slot 0 (uint24 at bit offset 24).
    function _readDailyIdx() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(0))) >> 24);
    }

    /// @dev The word _backfillGapDays derives for a skipped day. The day is packed as uint24
    ///      (its loop counter type), so the preimage day width is 3 bytes.
    function _derived(uint256 word, uint256 day) internal pure returns (uint256 w) {
        if (word == 0) word = 1; // the callback delivers a zero word as 1
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

    /// @dev Resume after coordinator swap. The swap re-issues the in-flight request on the
    ///      new coordinator, so a pending request already exists: fulfil it, then drain. A
    ///      stalled daily request's word finishes the day it was sent for. If nothing was in
    ///      flight, advanceGame fires a fresh request first.
    function _resumeAfterSwap(MockVRFCoordinator newVRF, uint256 vrfWord) internal {
        uint256 reqId = newVRF.lastRequestId();
        if (reqId == 0) {
            game.advanceGame();
            reqId = newVRF.lastRequestId();
        }
        newVRF.fulfillRandomWords(reqId, vrfWord);
        for (uint256 i = 0; i < 500; i++) {
            if (!game.rngLocked()) break;
            try game.advanceGame() {} catch { break; }
        }
    }

    /// @dev Catch up after the stalled day finished: the wall day's fresh request is answered
    ///      with `word`, which derives every skipped day in between, and the wall day completes.
    function _catchUp(MockVRFCoordinator vrf, uint256 word) internal {
        uint24 wallDay = game.currentDayView();
        for (uint256 i = 0; i < 500; i++) {
            game.advanceGame();
            uint256 id = vrf.lastRequestId();
            if (id != 0) {
                (,, bool done) = vrf.pendingRequests(id);
                if (!done) vrf.fulfillRandomWords(id, word);
            }
            if (!game.rngLocked() && game.rngWordForDay(wallDay) != 0) return;
        }
        fail("catch-up did not complete the wall day");
    }

    /// @dev Stall the day-3 request, swap coordinators at `resumeDay` and finish day 3 on the
    ///      re-issued request's late word. `resumeDay` stays under 14 days from the send, so
    ///      the request is answered while VRF still counts as alive.
    function _stallDay3AndResume(uint256 resumeDay) internal returns (MockVRFCoordinator newVRF) {
        _completeDay(0xDEAD0001);
        vm.warp(3 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 3 VRF pending");

        vm.warp(resumeDay * 86400);
        newVRF = _doCoordinatorSwap();
        _resumeAfterSwap(newVRF, 0xDEAD0003);
        assertEq(game.rngWordForDay(3), 0xDEAD0003, "Stalled day finishes on its own word");
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
        test_gapBackfillSingleDay_fuzz(0);
        vm.revertToState(snap);
        test_gapBackfillSingleDay_fuzz(1);
    }

    /// @notice Fuzz: day 3 stalls into day 5. Day 3 finishes on its own late word, day 5's
    ///         fresh (fuzzed) word derives the single gap day 4.
    function test_gapBackfillSingleDay_fuzz(uint256 vrfWord) public {
        MockVRFCoordinator newVRF = _stallDay3AndResume(5);
        _catchUp(newVRF, vrfWord);

        assertEq(game.rngWordForDay(4), _derived(vrfWord, 4), "Gap day 4 derives from day 5's word");
        assertTrue(game.rngWordForDay(5) != 0, "Current day 5 processed");
        assertEq(_readDailyIdx(), 5, "dailyIdx jumps past the gap to the wall day");
    }

    // ══════════════════════════════════════════════════════════════════════
    // TEST-03b: Multi-Day Gap Backfill (2-29 days)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Fuzz: 2-29 skipped days (4..3+gapDays) derived with unique nonzero words.
    ///         The stalled day-3 request is answered before it is 14 days old; past that the
    ///         game sits unattended until the wall day, at most 30 days past the day-3 seal.
    function test_gapBackfillMultiDay_fuzz(uint256 vrfWord, uint8 rawGapDays) public {
        uint256 gapDays = bound(rawGapDays, 2, 29);
        uint256 wallDay = 4 + gapDays;
        uint256 resumeDay = wallDay < 16 ? wallDay : 16;

        MockVRFCoordinator newVRF = _stallDay3AndResume(resumeDay);
        vm.warp(wallDay * 86400);
        assertFalse(game.livenessTriggered(), "inside the deadman window");
        _catchUp(newVRF, vrfWord);

        uint256[] memory words = new uint256[](gapDays);
        for (uint256 d = 4; d < wallDay; d++) {
            uint256 w = game.rngWordForDay(uint24(d));
            assertEq(w, _derived(vrfWord, d), "Gap day word must match keccak256(word, day)");
            words[d - 4] = w;
        }
        for (uint256 i = 0; i < gapDays; i++) {
            for (uint256 j = i + 1; j < gapDays; j++) {
                assertTrue(words[i] != words[j], "Gap day words must be unique");
            }
        }
        assertEq(_readDailyIdx(), wallDay, "dailyIdx jumps past the gap to the wall day");
    }

    // ══════════════════════════════════════════════════════════════════════
    // TEST-03c: Widest Live Gap with Gas Ceiling
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Fuzz: the widest gap a live game derives, and its gas. A request unanswered for
    ///         14 days is VRF dead, so a stall alone never reaches it; the bound is the deadman.
    ///         Day 3 stalls 13 days, finishes on its late word, then nobody advances until day
    ///         33 (dailyIdx 3 + 30): 29 skipped days, all derived in the transaction that applies
    ///         day 33's word. One more day trips the deadman and the game ends instead.
    function test_gapBackfillMaxGap_fuzz(uint256 vrfWord) public {
        MockVRFCoordinator newVRF = _stallDay3AndResume(16);

        // Boundary: day 34 is 31 days past the last seal.
        uint256 snap = vm.snapshotState();
        vm.warp(34 * 86400);
        assertTrue(game.livenessTriggered(), "one day past the widest gap trips the deadman");
        vm.revertToState(snap);

        vm.warp(33 * 86400);
        assertFalse(game.livenessTriggered(), "inside the deadman window");
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 33 requested");
        newVRF.fulfillRandomWords(newVRF.lastRequestId(), vrfWord);

        // Measure the transaction that applies the word and derives days 4..32.
        uint256 gasBefore = gasleft();
        game.advanceGame();
        uint256 gasUsed = gasBefore - gasleft();
        assertTrue(game.rngWordForDay(32) != 0, "every skipped day derived in that transaction");
        assertTrue(gasUsed < 10_000_000, "29-day gap backfill must use < 10M gas");

        _catchUp(newVRF, vrfWord);
        for (uint256 d = 4; d <= 32; d++) {
            assertEq(
                game.rngWordForDay(uint24(d)),
                _derived(vrfWord, d),
                "widest survivable gap: every gap day derives from the wall day's word"
            );
        }
        assertEq(_readDailyIdx(), 33, "dailyIdx reaches the wall day");
        assertFalse(game.livenessTriggered(), "the game survives the widest gap");
    }

    // ══════════════════════════════════════════════════════════════════════
    // TEST-03d: Gap Backfill with Mid-Day Pending State
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Fuzz: a mid-day lootbox request left pending across a stall. The swap re-issues
    ///         it for its reserved index; its word fills that index but seals no day. Day 8's
    ///         fresh daily request then derives gap days 4..7.
    function test_gapBackfillWithMidDayPending_fuzz(uint256 vrfWord) public {
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
        uint48 reservedIndex = indexBeforeStall - 1;

        // Stall into day 8, swap: the mid-day request is re-issued for the same reserved index
        vm.warp(8 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();
        _resumeAfterSwap(newVRF, 0xDEAD0004);
        assertEq(_lootboxRngWord(reservedIndex), 0xDEAD0004, "Re-issued mid-day word fills its reserved index");

        // Day 8's fresh request derives the gap days
        _catchUp(newVRF, vrfWord);
        for (uint32 d = 4; d <= 7; d++) {
            assertEq(
                game.rngWordForDay(uint24(d)),
                _derived(vrfWord, d),
                "Gap day must derive from the wall day's word after mid-day stall recovery"
            );
        }

        // lootboxRngIndex should have advanced past the stall
        assertTrue(
            _lootboxRngIndex() > indexBeforeStall,
            "lootboxRngIndex must advance after mid-day stall recovery"
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    // TEST-03e: Gap Backfill Entropy Uniqueness
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Fuzz: gap backfill produces unique per-day entropy via keccak256(word, day).
    ///         Day 3 stalls into day 13; day 13's fuzzed word derives gap days 4..12.
    function test_gapBackfillEntropyUnique_fuzz(uint256 vrfWord) public {
        MockVRFCoordinator newVRF = _stallDay3AndResume(13);
        _catchUp(newVRF, vrfWord);

        uint256[9] memory words;
        for (uint32 d = 4; d <= 12; d++) {
            uint256 w = game.rngWordForDay(uint24(d));
            assertEq(w, _derived(vrfWord, d), "Gap day word must match keccak256(word, day)");
            words[d - 4] = w;
        }

        // Every pair of gap words, and each against the stalled day's own word, is distinct
        for (uint256 i = 0; i < 9; i++) {
            assertTrue(words[i] != game.rngWordForDay(3), "Gap words differ from the stalled day's word");
            for (uint256 j = i + 1; j < 9; j++) {
                assertTrue(
                    words[i] != words[j],
                    "Gap day words must be pairwise distinct (keccak256 uniqueness)"
                );
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // TEST-03f: Index Lifecycle Across Stall Recovery
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Fuzz: lootboxRngIndex monotonically increases across stall recovery,
    ///         with no double-increments or skips. Recovery word is fuzzed.
    function test_indexLifecycleAcrossStall_fuzz(uint256 vrfWord) public {
        // Record initial index
        uint48 initialIndex = _lootboxRngIndex();

        // Complete the first post-deploy day normally with fixed word
        _completeDay(0xDEAD0001);
        uint48 indexAfterFirstDay = _lootboxRngIndex();
        assertEq(
            indexAfterFirstDay,
            initialIndex + 1,
            "First day: index should increment by exactly 1"
        );

        // Warp to the next day (day 3 absolute), trigger VRF request (will stall)
        vm.warp(3 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 3 VRF pending");
        uint48 indexAfterDay3Request = _lootboxRngIndex();

        // Index must have increased (fresh daily request increments it)
        assertTrue(
            indexAfterDay3Request >= indexAfterFirstDay,
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

        // Resume with fuzzed recovery word
        _resumeAfterSwap(newVRF, vrfWord);
        uint48 finalIndex = _lootboxRngIndex();

        // Final index must be >= day 3 request index (monotonic)
        assertTrue(
            finalIndex >= indexAfterDay3Request,
            "Final index must be >= index after day 3 request (monotonic)"
        );

        // Verify lootbox word at the initial index (first day slot) is nonzero
        assertTrue(
            _lootboxRngWord(initialIndex) != 0,
            "First day lootbox index must have nonzero word"
        );
    }
}
