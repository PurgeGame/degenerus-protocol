// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
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

    /// @dev Read lootboxRngIndex directly from storage slot 40.
    function _lootboxRngIndex() internal view returns (uint48) {
        return uint48(uint256(vm.load(address(game), bytes32(uint256(40)))));
    }

    /// @dev Read lootboxRngWordByIndex[index] from storage (mapping at slot 44).
    function _lootboxRngWord(uint48 index) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(44)));
        return uint256(vm.load(address(game), slot));
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

    // ── TEST-02: Coinflip claims across gap days ────────────────────

    /// @notice Proves coinflip stakes placed before/during stall resolve after
    ///         backfill -- getCoinflipDayResult returns non-zero rewardPercent
    ///         for each gap day.
    function test_coinflipClaimsAcrossGapDays() public {
        // Setup buyer
        address buyer = makeAddr("flipBuyer");
        vm.deal(buyer, 100 ether);

        // Day 1: purchase 5 tickets (stakes go to day 2 via _targetFlipDay = currentDayView()+1)
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(buyer);
            game.purchase{value: 0.01 ether}(buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth);
        }

        // Complete day 1
        _completeDay(0xF11F0001);

        // Warp to day 2, trigger VRF request (will stall)
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF pending");

        // Purchase during stall at day 2 (stakes go to day 3)
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(buyer);
            game.purchase{value: 0.01 ether}(buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth);
        }

        // Warp +1 day (still stalled), purchase at day 3 (stakes go to day 4)
        vm.warp(block.timestamp + 1 days);
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(buyer);
            game.purchase{value: 0.01 ether}(buyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth);
        }

        // Warp +2 more days to create the full gap (now at day 5)
        // _stallAndSwap would warp again, so just do coordinator swap directly
        vm.warp(block.timestamp + 2 days);
        MockVRFCoordinator newVRF = _doCoordinatorSwap();

        // Resume
        _resumeAfterSwap(newVRF, 0xF11FCAFE);

        // Verify coinflip results populated for gap days.
        // processCoinflipPayouts always writes coinflipDayResult (rewardPercent >= 50).
        // Gap days 2,3,4 should be processed by _backfillGapDays.
        (uint16 reward2,) = coinflip.getCoinflipDayResult(2);
        (uint16 reward3,) = coinflip.getCoinflipDayResult(3);
        (uint16 reward4,) = coinflip.getCoinflipDayResult(4);

        assertTrue(reward2 != 0, "Day 2 coinflip resolved after backfill");
        assertTrue(reward3 != 0, "Day 3 coinflip resolved after backfill");
        assertTrue(reward4 != 0, "Day 4 coinflip resolved after backfill");
    }

    // ── TEST-03: Lootbox open after orphaned index backfill ─────────

    /// @notice Proves lootbox at orphaned RNG index has non-zero rngWord after
    ///         coordinator swap, and openLootBox does not revert with RngNotReady.
    function test_lootboxOpenAfterOrphanedIndexBackfill() public {
        // Setup buyer with enough ETH for lootbox purchases
        address buyer = makeAddr("lootBuyer");
        vm.deal(buyer, 200 ether);

        // Day 1: purchase with lootbox amount
        // lootboxRngIndex = 1, so this writes to lootboxEth[1][buyer]
        vm.prank(buyer);
        game.purchase{value: 1.01 ether}(buyer, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth);

        // Complete day 1 (VRF request reserves lootbox index 1, fulfillment writes word for index 1)
        // After this: lootboxRngIndex = 2
        _completeDay(0x10070001);

        // Record the current lootbox index (should be 2 now)
        uint48 preStallIndex = _lootboxRngIndex();

        // Warp to day 2
        vm.warp(block.timestamp + 1 days);

        // Purchase with lootbox amount BEFORE advanceGame so lootboxEth[preStallIndex][buyer] has value
        // lootboxRngIndex is still preStallIndex (2), so this writes to lootboxEth[2][buyer]
        vm.prank(buyer);
        game.purchase{value: 1.01 ether}(buyer, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth);

        // advanceGame triggers VRF request, which reserves lootbox index preStallIndex (2)
        // and increments lootboxRngIndex to 3
        game.advanceGame();
        assertTrue(game.rngLocked(), "Day 2 VRF pending");

        // The orphaned index is preStallIndex (reserved by the day 2 VRF request)
        uint48 orphanedIndex = preStallIndex;

        // Verify no RNG word yet for orphaned index
        assertEq(_lootboxRngWord(orphanedIndex), 0, "Orphaned index has no RNG word before swap");

        // Stall + swap (warp 3 days, coordinator swap saves orphaned index but does NOT backfill yet)
        MockVRFCoordinator newVRF = _stallAndSwap(3);

        // After swap: orphaned index is still 0 — backfill uses VRF entropy, not on-chain state
        assertEq(_lootboxRngWord(orphanedIndex), 0, "Orphaned index NOT yet backfilled (deferred to rngGate)");

        // Resume: rngGate backfills gap days AND orphaned lootbox index using fresh VRF word
        _resumeAfterSwap(newVRF, 0x1007CAFE);

        // After resume: orphaned index should now have a VRF-derived word
        assertTrue(_lootboxRngWord(orphanedIndex) != 0, "Orphaned index backfilled after resume with VRF entropy");

        // Verify openLootBox does not revert for the orphaned index.
        vm.prank(buyer);
        game.openLootBox(buyer, orphanedIndex);
    }
}
