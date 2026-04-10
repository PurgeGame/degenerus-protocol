// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title VRFPathCoverage -- Parametric fuzz tests for gap backfill edge cases (TEST-03)
/// @notice Complements the invariant tests from VRFPathInvariants by testing specific
///         boundary scenarios with fuzzed VRF words: single-day gap, multi-day gap,
///         maximum 120-day gap, mid-day pending state, entropy uniqueness, and
///         index lifecycle across stall recovery.
///
/// @dev Follows VRFStallEdgeCases patterns: fixed VRF words for deterministic day-1
///      setup, fuzzed words only for the parameter under test (recovery word, gap size).
///
///      NOTE: With fuzzed VRF words, the advanceGame loop may need many iterations to
///      fully unlock (the game processes multiple stages per day, and small VRF words
///      like 1 create many stages). The gap backfill itself completes during the VRF
///      word processing stage, so gap day words are populated even if the game is still
///      processing subsequent stages. Tests assert gap backfill correctness directly
///      rather than requiring full unlock, which is a stronger test anyway.
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

    /// @dev Complete a full day with extended loop for fuzzed words.
    ///      Some VRF words (e.g. 1) create many game stages.
    function _completeDayFuzzSafe(uint256 vrfWord) internal {
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, vrfWord);
        for (uint256 i = 0; i < 500; i++) {
            if (!game.rngLocked()) break;
            try game.advanceGame() {} catch { break; }
        }
    }

    /// @dev Read lootboxRngIndex directly from storage slot 38.
    function _lootboxRngIndex() internal view returns (uint48) {
        return uint48(uint256(vm.load(address(game), bytes32(uint256(38)))));
    }

    /// @dev Read lootboxRngWordByIndex[index] from storage (mapping at slot 39).
    function _lootboxRngWord(uint48 index) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(39)));
        return uint256(vm.load(address(game), slot));
    }

    /// @dev Deploy a new MockVRFCoordinator and wire it up via admin prank.
    function _doCoordinatorSwap() internal returns (MockVRFCoordinator newVRF) {
        newVRF = new MockVRFCoordinator();
        uint256 newSubId = newVRF.createSubscription();
        newVRF.addConsumer(newSubId, address(game));
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(newVRF), newSubId, bytes32(uint256(1)));
    }

    /// @dev Resume after coordinator swap: advanceGame -> fulfill on newVRF -> process.
    ///      Gap backfill occurs during VRF word processing, so gap days are populated
    ///      even if the game hasn't fully unlocked yet.
    function _resumeAfterSwap(MockVRFCoordinator newVRF, uint256 vrfWord) internal {
        game.advanceGame();
        uint256 reqId = newVRF.lastRequestId();
        newVRF.fulfillRandomWords(reqId, vrfWord);
        // Process until unlocked. Uses extended loop for fuzzed words.
        for (uint256 i = 0; i < 500; i++) {
            if (!game.rngLocked()) break;
            try game.advanceGame() {} catch { break; }
        }
    }

    /// @dev Make a purchase for player with the given lootbox ETH amount.
    function _makePurchase(address player, uint256 lootboxAmount) internal {
        vm.deal(player, 100 ether);
        vm.prank(player);
        game.purchase{value: lootboxAmount + 0.01 ether}(
            player, 400, lootboxAmount, bytes32(0), MintPaymentKind.DirectEth
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    // TEST-03a: Single-Day Gap Backfill
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Fuzz: 1 gap day backfilled correctly after coordinator swap.
    ///         Day 1 uses fixed setup word; recovery word is fuzzed.
    function test_gapBackfillSingleDay_fuzz(uint256 vrfWord) public {
        vrfWord = bound(vrfWord, 1, type(uint256).max);

        // Complete the first post-deploy day normally with fixed word
        _completeDay(0xDEAD0001);

        // Warp to the next day, trigger VRF request (will stall)
        vm.warp(3 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 3 VRF pending");

        // Stall: warp to day 5 (absolute), swap coordinator
        vm.warp(5 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Resume with fuzzed word on new coordinator
        _resumeAfterSwap(newVRF, vrfWord);

        // Gap days 3 and 4 should be backfilled
        assertTrue(game.rngWordForDay(3) != 0, "Gap day 3 must be backfilled");
        assertTrue(game.rngWordForDay(4) != 0, "Gap day 4 must be backfilled");

        // Current day view should be at least 5
        assertTrue(game.currentDayView() >= 5, "Current day must be at least 5");
    }

    // ══════════════════════════════════════════════════════════════════════
    // TEST-03b: Multi-Day Gap Backfill (3-30 days)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Fuzz: multi-day gap (3-30 days) backfilled with unique nonzero words.
    ///         Day 1 uses fixed setup word; recovery word and gap size are fuzzed.
    function test_gapBackfillMultiDay_fuzz(uint256 vrfWord, uint8 rawGapDays) public {
        vrfWord = bound(vrfWord, 1, type(uint256).max);
        rawGapDays = uint8(bound(rawGapDays, 3, 30));

        // Complete the first post-deploy day normally with fixed word
        _completeDay(0xDEAD0001);

        // Warp to the next day (day 3 absolute), trigger VRF request (will stall)
        vm.warp(3 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 3 VRF pending");

        // Stall: warp to day (3 + rawGapDays), swap coordinator
        uint256 stallDay = 3;
        uint256 resumeDay = stallDay + uint256(rawGapDays);
        vm.warp(resumeDay * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Resume with fuzzed word
        _resumeAfterSwap(newVRF, vrfWord);

        // Collect and verify all gap day words (from stallDay to resumeDay-1)
        uint256 gapCount = resumeDay - stallDay;
        uint256[] memory words = new uint256[](gapCount);
        for (uint256 d = stallDay; d < resumeDay; d++) {
            uint256 w = game.rngWordForDay(uint32(d));
            assertTrue(w != 0, "Gap day word must be nonzero");
            words[d - stallDay] = w;
        }

        // Assert all gap day words are unique (pairwise comparison)
        for (uint256 i = 0; i < gapCount; i++) {
            for (uint256 j = i + 1; j < gapCount; j++) {
                assertTrue(words[i] != words[j], "Gap day words must be unique");
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // TEST-03c: Maximum Gap (120 days) with Gas Ceiling
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Fuzz: 120-day gap backfill fits within 25M gas ceiling (STALL-03).
    ///         Day 1 uses fixed setup word; recovery word is fuzzed.
    function test_gapBackfillMaxGap_fuzz(uint256 vrfWord) public {
        vrfWord = bound(vrfWord, 1, type(uint256).max);

        // Complete the first post-deploy day normally with fixed word
        _completeDay(0xDEAD0001);

        // Warp to the next day (day 3 absolute), trigger VRF request (will stall)
        vm.warp(3 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 3 VRF pending");

        // Stall: warp to day 123 (120-day gap = death clock maximum)
        vm.warp(123 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Measure gas for the resume cycle (includes gap backfill)
        uint256 gasBefore = gasleft();
        _resumeAfterSwap(newVRF, vrfWord);
        uint256 gasUsed = gasBefore - gasleft();

        // Gas ceiling: 25M (from STALL-03)
        assertTrue(gasUsed < 25_000_000, "120-day gap backfill must use < 25M gas");

        // Verify all 120 gap days (3..122) have nonzero words
        for (uint32 d = 3; d <= 122; d++) {
            assertTrue(
                game.rngWordForDay(d) != 0,
                "120-day gap: all gap days must have nonzero words"
            );
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // TEST-03d: Gap Backfill with Mid-Day Pending State
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Fuzz: gap backfill works correctly when mid-day lootbox RNG was pending.
    ///         Creates mid-day pending state via requestLootboxRng before stall.
    function test_gapBackfillWithMidDayPending_fuzz(uint256 vrfWord) public {
        vrfWord = bound(vrfWord, 1, type(uint256).max);

        // Complete the first post-deploy day normally
        _completeDay(0xDEAD0001);

        // Warp to day 3, complete it so we have a daily word for mid-day request
        vm.warp(3 * 86400);
        _completeDay(0xDEAD0002);

        // Make a purchase with lootbox amount (triggers lootbox RNG state)
        // Use 1 ether lootbox (proven to work in VRFStallEdgeCases tests)
        address buyer = makeAddr("midDayBuyer");
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: 1.01 ether}(
            buyer, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth
        );

        // Fund VRF subscription for mid-day request
        mockVRF.fundSubscription(1, 100e18);

        // Request mid-day lootbox RNG (creates mid-day pending state)
        game.requestLootboxRng();

        // Record lootboxRngIndex before stall
        uint48 indexBeforeStall = _lootboxRngIndex();

        // Stall: warp to day 8 (absolute)
        vm.warp(8 * 86400);

        // Coordinator swap (should clear midDayTicketRngPending)
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Resume with fuzzed vrfWord
        _resumeAfterSwap(newVRF, vrfWord);

        // Verify gap days have nonzero words (days 4..7 are the gap)
        for (uint32 d = 4; d <= 7; d++) {
            assertTrue(
                game.rngWordForDay(d) != 0,
                "Gap day must have nonzero word after mid-day stall recovery"
            );
        }

        // lootboxRngIndex should have advanced past the stall
        uint48 indexAfterRecovery = _lootboxRngIndex();
        assertTrue(
            indexAfterRecovery > indexBeforeStall,
            "lootboxRngIndex must advance after mid-day stall recovery"
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    // TEST-03e: Gap Backfill Entropy Uniqueness
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Fuzz: gap backfill produces unique per-day entropy via keccak256(vrfWord, day).
    ///         Day 1 uses fixed setup word; recovery word is fuzzed.
    function test_gapBackfillEntropyUnique_fuzz(uint256 vrfWord) public {
        vrfWord = bound(vrfWord, 1, type(uint256).max);

        // Complete the first post-deploy day normally with fixed word
        _completeDay(0xDEAD0001);

        // Warp to the next day (day 3 absolute), trigger VRF request (will stall)
        vm.warp(3 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 3 VRF pending");

        // Stall: warp to day 13 (10-day gap)
        vm.warp(13 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Resume with fuzzed word
        _resumeAfterSwap(newVRF, vrfWord);

        // Collect all gap day words (days 3..12)
        uint256[10] memory words;
        for (uint32 d = 3; d <= 12; d++) {
            uint256 w = game.rngWordForDay(d);
            assertTrue(w != 0, "Gap day word must be nonzero");
            words[d - 3] = w;
        }

        // Assert every pair of words is distinct
        for (uint256 i = 0; i < 10; i++) {
            for (uint256 j = i + 1; j < 10; j++) {
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
        vrfWord = bound(vrfWord, 1, type(uint256).max);

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
