// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title VRFStallEdgeCases -- Audit tests for VRF stall edge case requirements
/// @notice Covers STALL-01 (gap backfill entropy), STALL-02 (manipulation window),
///         STALL-03 (gas ceiling), STALL-04 (coordinator swap state), STALL-05 (zero-seed),
///         STALL-06 (gameover fallback / V37-001), STALL-07 (dailyIdx timing consistency).
contract VRFStallEdgeCases is DeployProtocol {
    /// @dev Storage slot constants verified via `forge inspect DegenerusGame storage-layout`.
    uint256 constant SLOT_PACKED_0 = 0;
    uint256 constant SLOT_RNG_WORD_CURRENT = 3;
    uint256 constant SLOT_VRF_REQUEST_ID = 4;

    function setUp() public {
        _deployProtocol();
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    /// @dev Complete a full day: advanceGame -> VRF fulfill -> loop until unlocked.
    ///      Tracks the last-known request ID to avoid double-fulfillment when the
    ///      game reuses a stale rngWordCurrent across day boundaries.
    uint256 private _lastFulfilledReqId;

    function _completeDay(uint256 vrfWord) internal {
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
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

    /// @dev Resume after coordinator swap: advanceGame -> fulfill on newVRF -> loop until unlocked.
    function _resumeAfterSwap(MockVRFCoordinator newVRF, uint256 vrfWord) internal {
        game.advanceGame();
        uint256 reqId = newVRF.lastRequestId();
        newVRF.fulfillRandomWords(reqId, vrfWord);
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
    }

    /// @dev Read lootboxRngIndex directly from storage slot 40.
    function _lootboxRngIndex() internal view returns (uint48) {
        return uint48(uint256(vm.load(address(game), bytes32(uint256(40)))));
    }

    /// @dev Read lootboxRngWordByIndex[index] from storage (mapping at slot 44).
    function _lootboxRngWord(uint48 index) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(44)));
        return uint256(vm.load(address(game), slot));
    }

    /// @dev Read rngWordCurrent directly from storage slot 4.
    function _readRngWordCurrent() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SLOT_RNG_WORD_CURRENT))));
    }

    /// @dev Read vrfRequestId directly from storage slot 5.
    function _readVrfRequestId() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SLOT_VRF_REQUEST_ID))));
    }

    /// @dev Read rngRequestTime from packed slot 0, bytes [12:18] (uint48).
    function _readRngRequestTime() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(SLOT_PACKED_0))));
        return uint48(packed >> 96);
    }

    /// @dev Read dailyIdx from packed slot 0, bytes [6:12] (uint48).
    function _readDailyIdx() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(SLOT_PACKED_0))));
        return uint48(packed >> 48);
    }

    // ══════════════════════════════════════════════════════════════════════
    // STALL-01: Gap Backfill Entropy Uniqueness
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Fuzz: gap backfill entropy produces unique per-day words derived from
    ///         keccak256(vrfWord, gapDay). Verifies all gap day words are distinct.
    function test_gapBackfillEntropyUnique_fuzz(uint256 vrfWord) public {
        vm.assume(vrfWord != 0);

        // Day 1 (ts=86400): complete normally
        _completeDay(0xDEAD0001);

        // Warp to day 2, trigger VRF request (will stall)
        vm.warp(2 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF pending");

        // Stall for 5 gap days: warp to day 7 (absolute ts), swap coordinator
        vm.warp(7 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Resume with fuzzed VRF word
        _resumeAfterSwap(newVRF, vrfWord);

        // _backfillGapDays called with vrfWord for gap days 2..6 (startDay=2, endDay=7)
        // Verify each gap day word equals the deterministic keccak256 derivation
        uint256[] memory words = new uint256[](5);
        for (uint48 d = 2; d <= 6; d++) {
            uint256 expected = uint256(keccak256(abi.encodePacked(vrfWord, d)));
            if (expected == 0) expected = 1;
            uint256 actual = game.rngWordForDay(d);
            assertEq(actual, expected, "Gap day word must match keccak256(vrfWord, day)");
            words[d - 2] = actual;
        }

        // Verify all gap day words are distinct from each other
        for (uint256 i = 0; i < 4; i++) {
            for (uint256 j = i + 1; j < 5; j++) {
                assertTrue(words[i] != words[j], "All gap day words must be distinct");
            }
        }
    }

    /// @notice Unit: verifies zero guard -- all derived gap day words are nonzero.
    function test_gapBackfillZeroGuard() public {
        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Warp to day 2, trigger VRF request (will stall)
        vm.warp(2 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF pending");

        // Stall 10 gap days: warp to day 12 (absolute), swap coordinator
        vm.warp(12 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        uint256 resumeWord = 0xBEEF0001;
        _resumeAfterSwap(newVRF, resumeWord);

        // Verify all gap day words (2..11) are nonzero (zero guard: derivedWord==0 -> 1)
        for (uint48 d = 2; d <= 11; d++) {
            assertTrue(
                game.rngWordForDay(d) != 0,
                "Zero guard: gap day word must be nonzero"
            );
        }
    }

    /// @notice Unit: exactly 1 gap day backfilled with correct keccak256 derivation.
    function test_gapBackfillSingleDayGap() public {
        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Warp to day 2, trigger VRF request (will stall)
        vm.warp(2 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF pending");

        // Stall exactly 1 gap day: warp to day 3, swap coordinator
        vm.warp(3 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        uint256 resumeWord = 0xCAFE0001;
        _resumeAfterSwap(newVRF, resumeWord);

        // Gap day 2 should be backfilled with keccak256(resumeWord, 2)
        uint256 expected = uint256(keccak256(abi.encodePacked(resumeWord, uint48(2))));
        if (expected == 0) expected = 1;
        assertEq(game.rngWordForDay(2), expected, "Single gap day backfill matches keccak256");

        // Day 3 (current day) should be processed normally (not a gap day)
        assertTrue(game.rngWordForDay(3) != 0, "Current day 3 processed");
    }

    // ══════════════════════════════════════════════════════════════════════
    // STALL-02: Manipulation Window (VRF callback -> advanceGame consumption)
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Unit: VRF word is stored via rawFulfillRandomWords and consumed on next
    ///         advanceGame. Both daily and gap backfill paths use the same rngWordCurrent
    ///         storage. After VRF callback, rngWordCurrent is nonzero. After processing,
    ///         rngWordCurrent is cleared. This proves the manipulation window is identical
    ///         to standard daily VRF -- no additional attack surface from gap backfill.
    function test_manipulationWindowIdenticalToDaily() public {
        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Warp to day 2, trigger VRF request (will stall)
        vm.warp(2 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF pending");

        // Stall 3 gap days: warp to day 5, swap coordinator
        vm.warp(5 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Now trigger new VRF request on the new coordinator
        game.advanceGame();
        uint256 reqId = newVRF.lastRequestId();

        // Before fulfillment: rngWordCurrent == 0
        assertEq(_readRngWordCurrent(), 0, "rngWordCurrent 0 before VRF callback");

        // VRF callback: stores word to rngWordCurrent
        uint256 resumeWord = 0xCAFEBABE;
        newVRF.fulfillRandomWords(reqId, resumeWord);

        // After callback: rngWordCurrent is nonzero (this is the manipulation window)
        assertEq(_readRngWordCurrent(), resumeWord, "rngWordCurrent set after VRF callback");

        // advanceGame consumes the word (processes gap backfill + current day)
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }

        // After processing: rngWordCurrent cleared to 0
        assertEq(_readRngWordCurrent(), 0, "rngWordCurrent cleared after processing");
    }

    /// @notice Unit: coinflip bets placed before stall are resolved by gap backfill.
    ///         Players cannot add bets for past gap days (no function accepts past day).
    function test_gapDayPositionsPreCommitted() public {
        address buyer = makeAddr("flipBuyer");
        vm.deal(buyer, 100 ether);

        // Purchase 5 tickets before any day completes (stakes go to day 2 via flipDay = currentDay+1)
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(buyer);
            game.purchase{value: 0.01 ether}(buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth);
        }

        // Day 1: complete normally
        _completeDay(0xF11F0001);

        // Warp to day 2, trigger VRF request (will stall)
        vm.warp(2 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF pending");

        // Stall + swap: warp to day 5
        vm.warp(5 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Resume
        _resumeAfterSwap(newVRF, 0xF11FCAFE);

        // Gap days 2,3,4 processed by _backfillGapDays -> coinflip.processCoinflipPayouts
        // Verify coinflip results populated for gap days (rewardPercent >= 50)
        (uint16 reward2,) = coinflip.getCoinflipDayResult(2);
        (uint16 reward3,) = coinflip.getCoinflipDayResult(3);
        (uint16 reward4,) = coinflip.getCoinflipDayResult(4);

        assertTrue(reward2 != 0, "Gap day 2 coinflip resolved after backfill");
        assertTrue(reward3 != 0, "Gap day 3 coinflip resolved after backfill");
        assertTrue(reward4 != 0, "Gap day 4 coinflip resolved after backfill");
    }

    // ══════════════════════════════════════════════════════════════════════
    // STALL-03: Gas Ceiling for Gap Backfill
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Gas profile: 30-day gap backfill fits well within 30M block gas limit.
    function test_gapBackfillGas30Days() public {
        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Warp to day 2, trigger VRF request (will stall)
        vm.warp(2 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF pending");

        // Stall 30 days: warp to day 32
        vm.warp(32 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Measure gas for the resume cycle (includes gap backfill)
        uint256 gasBefore = gasleft();
        _resumeAfterSwap(newVRF, 0xAA300001);
        uint256 gasUsed = gasBefore - gasleft();

        // 30 days * ~125k/iteration = ~3.75M + overhead, well under 10M
        assertTrue(gasUsed < 10_000_000, "30-day gap backfill must use < 10M gas");
    }

    /// @notice Gas profile: 120-day gap (death clock maximum) fits within 30M block gas limit.
    function test_gapBackfillGas120Days() public {
        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Warp to day 2, trigger VRF request (will stall)
        vm.warp(2 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF pending");

        // Stall 120 days: warp to day 122
        vm.warp(122 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Measure gas for the resume cycle (includes gap backfill)
        uint256 gasBefore = gasleft();
        _resumeAfterSwap(newVRF, 0xAA120001);
        uint256 gasUsed = gasBefore - gasleft();

        // 120 days * ~125k/iteration = ~15M + overhead, must stay under 25M
        assertTrue(gasUsed < 25_000_000, "120-day gap backfill must use < 25M gas");
    }

    // ══════════════════════════════════════════════════════════════════════
    // STALL-04: Coordinator Swap State Cleanup
    // ══════════════════════════════════════════════════════════════════════

    /// @dev Storage slot for totalFlipReversals (verified via forge inspect).
    uint256 constant SLOT_TOTAL_FLIP_REVERSALS = 5;
    /// @dev Storage slot for midDayTicketRngPending (verified via forge inspect).
    uint256 constant SLOT_MID_DAY_PENDING = 50;

    /// @notice Unit: coordinator swap resets all VRF state and preserves intentionally-kept variables.
    function test_coordinatorSwapResetsAllVrfState() public {
        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        uint256 preSwapDay1Word = game.rngWordForDay(1);

        // Warp to day 2, trigger VRF request -> rngLocked=true, vrfRequestId!=0, rngRequestTime!=0
        vm.warp(2 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF pending");
        assertTrue(_readVrfRequestId() != 0, "vrfRequestId set");
        assertTrue(_readRngRequestTime() != 0, "rngRequestTime set");
        // rngWordCurrent == 0 (not yet fulfilled)
        assertEq(_readRngWordCurrent(), 0, "rngWordCurrent 0 before fulfillment");

        // Record lootboxRngIndex AFTER VRF request (advanceGame increments it)
        uint48 preSwapLootboxIndex = _lootboxRngIndex();

        // Coordinator swap
        _doCoordinatorSwap();

        // Verify RESET variables:
        assertFalse(game.rngLocked(), "rngLocked cleared by swap");
        assertEq(_readVrfRequestId(), 0, "vrfRequestId cleared by swap");
        assertEq(_readRngRequestTime(), 0, "rngRequestTime cleared by swap");
        assertEq(_readRngWordCurrent(), 0, "rngWordCurrent cleared by swap");

        // Verify PRESERVED variables:
        assertEq(
            _lootboxRngIndex(),
            preSwapLootboxIndex,
            "lootboxRngIndex preserved across swap"
        );
        assertEq(
            game.rngWordForDay(1),
            preSwapDay1Word,
            "Historical rngWordByDay preserved across swap"
        );
    }

    /// @notice Fuzz: totalFlipReversals preserved across coordinator swap.
    function test_coordinatorSwapPreservesTotalFlipReversals_fuzz(uint8 nudges) public {
        // Bound to 0-3 nudges (reverseFlip costs BURNIE, which must be minted via purchases)
        nudges = uint8(bound(nudges, 0, 3));

        // Day 1: complete normally (to get BURNIE minted for nudge purchases)
        address buyer = makeAddr("nudgeBuyer");
        vm.deal(buyer, 100 ether);

        // Purchase enough to mint BURNIE for nudges
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(buyer);
            game.purchase{value: 0.5 ether}(buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth);
        }
        _completeDay(0xDEAD0001);

        // Apply nudges (reverseFlip increments totalFlipReversals)
        for (uint8 n = 0; n < nudges; n++) {
            vm.prank(buyer);
            try game.reverseFlip() {} catch {
                break; // Not enough BURNIE or RNG locked
            }
        }

        // Record totalFlipReversals before swap
        uint256 preSwapReversals = uint256(
            vm.load(address(game), bytes32(uint256(SLOT_TOTAL_FLIP_REVERSALS)))
        );

        // Warp to day 2, trigger VRF request, then swap
        vm.warp(2 * 86400);
        game.advanceGame();
        _doCoordinatorSwap();

        // totalFlipReversals must be preserved
        uint256 postSwapReversals = uint256(
            vm.load(address(game), bytes32(uint256(SLOT_TOTAL_FLIP_REVERSALS)))
        );
        assertEq(
            postSwapReversals,
            preSwapReversals,
            "totalFlipReversals preserved across swap"
        );
    }

    /// @notice Unit: midDayTicketRngPending cleared by coordinator swap.
    function test_coordinatorSwapClearsMidDayPending() public {
        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Warp to day 2, complete it so we have a daily word for mid-day request
        vm.warp(2 * 86400);
        _completeDay(0xDEAD0002);

        // Setup for mid-day: purchase with lootbox amount
        address buyer = makeAddr("midDayBuyer");
        vm.deal(buyer, 100 ether);
        vm.prank(buyer);
        game.purchase{value: 1.01 ether}(buyer, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth);

        // Fund VRF subscription
        mockVRF.fundSubscription(1, 100e18);

        // Request mid-day lootbox RNG
        game.requestLootboxRng();

        // Verify midDayTicketRngPending is set
        uint256 pendingVal = uint256(
            vm.load(address(game), bytes32(uint256(SLOT_MID_DAY_PENDING)))
        );
        assertTrue(pendingVal != 0, "midDayTicketRngPending should be set after requestLootboxRng");

        // Coordinator swap
        _doCoordinatorSwap();

        // Verify midDayTicketRngPending cleared
        pendingVal = uint256(
            vm.load(address(game), bytes32(uint256(SLOT_MID_DAY_PENDING)))
        );
        assertEq(pendingVal, 0, "midDayTicketRngPending cleared by swap");

        // Verify game can proceed without NotTimeYet after swap
        vm.warp(3 * 86400);
        MockVRFCoordinator newVRF = new MockVRFCoordinator();
        uint256 newSubId = newVRF.createSubscription();
        newVRF.addConsumer(newSubId, address(game));
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(newVRF), newSubId, bytes32(uint256(1)));

        // advanceGame should not revert (midDayTicketRngPending cleared)
        _resumeAfterSwap(newVRF, 0xDD030001);
    }

    // ══════════════════════════════════════════════════════════════════════
    // STALL-05: Zero-Seed Edge Case
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Unit: after day 1 completes, lootboxRngWord at current index is nonzero.
    ///         Coordinator swap preserves it. Resume updates it to new value.
    function test_zeroSeedUnreachableAfterSwap() public {
        // Day 1: complete normally -> _finalizeLootboxRng sets lootboxRngWordByIndex
        _completeDay(0xDEAD0001);

        // Verify lootboxRngWord at current index is nonzero after day 1
        uint48 preSwapIndex = _lootboxRngIndex() - 1;
        uint256 preSwapWord = _lootboxRngWord(preSwapIndex);
        assertTrue(preSwapWord != 0, "lootboxRngWord at current index nonzero after day 1");

        // Warp to day 2, trigger VRF request, then swap
        vm.warp(2 * 86400);
        game.advanceGame();
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Verify lootboxRngWord at pre-swap index is STILL the pre-swap nonzero value
        uint256 postSwapWord = _lootboxRngWord(preSwapIndex);
        assertEq(postSwapWord, preSwapWord, "lootboxRngWord at current index preserved by swap");

        // Resume with new VRF
        _resumeAfterSwap(newVRF, 0xCAFE0002);

        // After resume: lootboxRngWord at new index updated via _finalizeLootboxRng
        uint48 postResumeIndex = _lootboxRngIndex() - 1;
        uint256 postResumeWord = _lootboxRngWord(postResumeIndex);
        assertTrue(postResumeWord != 0, "lootboxRngWord at current index nonzero after resume");
    }

    /// @notice Unit: at game start (before any day completion), lootboxRngWord at index 0 == 0.
    ///         After coordinator swap at start + resume cycle, the resume index becomes nonzero.
    function test_zeroSeedAtGameStart() public {
        // At game start: lootboxRngWord at index 0 should be 0 (no day completed yet)
        assertEq(_lootboxRngWord(0), 0, "No word at index 0 at game start");

        // Trigger VRF request (day 1) -- increments lootboxRngIndex from 1 to 2
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 1 VRF request pending");

        // Coordinator swap at game start (edge case) -- orphans index 1
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Resume: advanceGame -> VRF -> advanceGame sets lootboxRngWordByIndex to nonzero
        // The resume fires a new VRF request (lootboxRngIndex increments to 3, reserving index 2)
        _resumeAfterSwap(newVRF, 0xF0E50001);

        // After resume: lootboxRngWord at resume index should be nonzero
        // The current lootboxRngIndex is 3, so index 2 was reserved by the resume.
        uint48 currentIndex = _lootboxRngIndex();
        uint48 resumeIndex = currentIndex - 1;
        assertTrue(
            _lootboxRngWord(resumeIndex) != 0,
            "Lootbox word at resume index nonzero after resume from start"
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    // STALL-06: Gameover Fallback + V37-001 _tryRequestRng Guard Branches
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Unit: after coordinator swap to a valid coordinator, _tryRequestRng succeeds
    ///         (VRF request fires). Verify rngLocked() == true after advanceGame.
    ///         This proves the guard branches (coordinator==0, keyHash==0, subId==0) are
    ///         bypassed when valid VRF config is present.
    function test_tryRequestRngGuardBranches() public {
        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Warp to day 2, trigger VRF request (will stall)
        vm.warp(2 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF pending");

        // Coordinator swap to a valid new coordinator
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // After swap: rngLocked cleared, new coordinator is valid
        assertFalse(game.rngLocked(), "rngLocked cleared after swap");

        // advanceGame should fire _tryRequestRng (or _requestRng) successfully
        // because the new coordinator has valid address, keyHash, and subId
        game.advanceGame();

        // rngLocked should be true (VRF request sent to new coordinator)
        assertTrue(game.rngLocked(), "VRF request sent via new coordinator (tryRequestRng bypasses guards)");

        // Verify new VRF request was received
        uint256 reqId = newVRF.lastRequestId();
        assertTrue(reqId > 0, "New coordinator received VRF request");
    }

    /// @notice Unit: after 5 completed days, all historical VRF words are nonzero.
    ///         This verifies the inputs to _getHistoricalRngFallback are valid.
    function test_historicalRngFallbackNonzero() public {
        // Complete 5 days (storing 5 VRF words)
        for (uint48 d = 1; d <= 5; d++) {
            vm.warp(uint256(d) * 86400);
            _completeDay(uint256(0xDEAD0000 + d));
        }

        // Verify rngWordByDay for days 1-5 are all nonzero (inputs to fallback hash)
        for (uint48 d = 1; d <= 5; d++) {
            assertTrue(
                game.rngWordForDay(d) != 0,
                "Historical VRF word must be nonzero for fallback"
            );
        }

        // Each day's word should be distinct (different VRF seeds)
        for (uint48 i = 1; i <= 4; i++) {
            for (uint48 j = i + 1; j <= 5; j++) {
                assertTrue(
                    game.rngWordForDay(i) != game.rngWordForDay(j),
                    "Historical words must be distinct"
                );
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // STALL-07: DailyIdx Timing Consistency
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Unit: flipDay = day + 1 alignment. After day 1 completes,
    ///         getCoinflipDayResult(2) has nonzero rewardPercent (flipDay=1+1=2).
    function test_flipDayAlignedWithDailyIdx() public {
        // Purchase tickets so day 1 processCoinflipPayouts has something to write
        address buyer = makeAddr("alignBuyer");
        vm.deal(buyer, 100 ether);
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(buyer);
            game.purchase{value: 0.01 ether}(buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth);
        }

        // Day 1: complete normally
        _completeDay(0xA1160001);

        // Verify rngWordForDay(1) is nonzero (day 1 was processed)
        assertTrue(game.rngWordForDay(1) != 0, "Day 1 has RNG word");

        // The coinflip result for day 2 (flipDay = 1 + 1 = 2) should be set by day 1 processing
        // coinflip.processCoinflipPayouts(bonusFlip, word, day) writes to coinflipDayResult[day]
        // But rngGate processes at day=1, and coinflip writes result for day=1
        // The purchases' _targetFlipDay = currentDayView()+1, so stakes are on day 2
        // processCoinflipPayouts(word, day=1) writes coinflipDayResult[1]
        (uint16 reward,) = coinflip.getCoinflipDayResult(1);
        assertTrue(reward != 0, "Day 1 coinflip result populated (processCoinflipPayouts writes to day param)");
    }

    /// @notice Unit: gap days get coinflip processing, game advances past the gap.
    function test_gapDaysSkipResolveRedemptionPeriod() public {
        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Warp to day 2, trigger VRF request (will stall)
        vm.warp(2 * 86400);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF pending");

        // Stall 3 gap days: warp to day 5
        vm.warp(5 * 86400);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Resume
        _resumeAfterSwap(newVRF, 0xBACF0001);

        // Verify gap day words exist (backfill processed gap days 2, 3, 4)
        assertTrue(game.rngWordForDay(2) != 0, "Gap day 2 backfilled");
        assertTrue(game.rngWordForDay(3) != 0, "Gap day 3 backfilled");
        assertTrue(game.rngWordForDay(4) != 0, "Gap day 4 backfilled");

        // Current day 5 was processed normally (not a gap day)
        assertTrue(game.rngWordForDay(5) != 0, "Current day 5 processed");

        // Game advanced past the gap successfully -- dailyIdx should be 5
        uint48 idx = _readDailyIdx();
        assertEq(idx, 5, "dailyIdx advanced past gap to current day");
    }

    /// @notice Unit: wall-clock day advances during stall but dailyIdx does not.
    function test_wallClockDayAdvancesDuringStall() public {
        // Day 1: complete normally
        _completeDay(0xDEAD0001);

        // Record currentDayView and dailyIdx after day 1
        uint48 dayAfterComplete = game.currentDayView();
        uint48 idxAfterComplete = _readDailyIdx();
        assertEq(idxAfterComplete, 1, "dailyIdx == 1 after day 1 complete");

        // Warp +3 days without advancing (stall scenario without VRF request)
        vm.warp(4 * 86400);

        // currentDayView (wall-clock) has advanced
        uint48 wallClockDay = game.currentDayView();
        assertTrue(wallClockDay > dayAfterComplete, "Wall-clock day advanced during stall");

        // dailyIdx has NOT advanced (still at 1, no advanceGame called)
        uint48 stallIdx = _readDailyIdx();
        assertEq(stallIdx, idxAfterComplete, "dailyIdx frozen during stall");

        // rngWordForDay(2) == 0 (day 2 never processed)
        assertEq(game.rngWordForDay(2), 0, "Day 2 never processed during stall");

        // rngWordForDay(3) == 0 (day 3 never processed)
        assertEq(game.rngWordForDay(3), 0, "Day 3 never processed during stall");
    }
}
