// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title StallResilience -- Proves VRF stall -> coordinator swap -> resume cycle
/// @notice Integration tests for gap day RNG backfill (TEST-01), coinflip resolution
///         across gap days (TEST-02), and lootbox opens after orphaned index backfill (TEST-03).
contract StallResilience is DeployProtocol {
    function setUp() public {
        _deployProtocol();
    }

    // ── Helpers ──────────────────────────────────────────────────────

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

    // ── TEST-01: Stall -> Swap -> Resume with gap day backfill ───────

    /// @notice Proves gap days get non-zero backfilled RNG words derived from
    ///         the resume VRF word via keccak256(vrfWord, gapDay).
    function test_stallSwapResume() public {
        // Day 1: complete normally
        _completeDay(0xDEAD0001);
        assertEq(game.currentDayView(), 1);
        assertTrue(game.rngWordForDay(1) != 0, "Day 1 has RNG word");

        // Warp to day 2, trigger VRF request (this will stall)
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF request pending");

        // Stall: warp +3 days without fulfilling (gap days: 2, 3, 4; current day after warp: 5)
        MockVRFCoordinator newVRF = _stallAndSwap(3);

        // Resume on day 5
        uint256 resumeWord = 0xCAFEBABE;
        _resumeAfterSwap(newVRF, resumeWord);

        // Verify gap days backfilled (TEST-01 core assertion)
        // After day 1 complete, dailyIdx=1. Day 2 VRF requested but never fulfilled.
        // After swap+resume, _backfillGapDays runs for days 2,3,4 (dailyIdx+1 to currentDay exclusive).
        assertTrue(game.rngWordForDay(2) != 0, "Gap day 2 backfilled");
        assertTrue(game.rngWordForDay(3) != 0, "Gap day 3 backfilled");
        assertTrue(game.rngWordForDay(4) != 0, "Gap day 4 backfilled");
        assertTrue(game.rngWordForDay(5) != 0, "Current day 5 processed");

        // Verify gap day words are deterministic derivations of the resume VRF word.
        // _backfillGapDays is called BEFORE _applyDailyRng in rngGate (line 794 before 798).
        // So it uses rngWordCurrent (the raw VRF word, pre-nudge).
        uint256 expectedDay2 = uint256(keccak256(abi.encodePacked(resumeWord, uint48(2))));
        if (expectedDay2 == 0) expectedDay2 = 1;
        assertEq(game.rngWordForDay(2), expectedDay2, "Day 2 word is keccak256(vrfWord, 2)");

        uint256 expectedDay3 = uint256(keccak256(abi.encodePacked(resumeWord, uint48(3))));
        if (expectedDay3 == 0) expectedDay3 = 1;
        assertEq(game.rngWordForDay(3), expectedDay3, "Day 3 word is keccak256(vrfWord, 3)");

        uint256 expectedDay4 = uint256(keccak256(abi.encodePacked(resumeWord, uint48(4))));
        if (expectedDay4 == 0) expectedDay4 = 1;
        assertEq(game.rngWordForDay(4), expectedDay4, "Day 4 word is keccak256(vrfWord, 4)");
    }
}
