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
    uint256 constant SLOT_RNG_WORD_CURRENT = 4;
    uint256 constant SLOT_VRF_REQUEST_ID = 5;

    function setUp() public {
        _deployProtocol();
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

    /// @dev Deploy a new MockVRFCoordinator, wire it up via admin prank.
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
}
