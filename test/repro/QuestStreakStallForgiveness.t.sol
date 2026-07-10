// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title QuestStreakStallForgiveness
/// @notice Regression coverage for unrolled quest days and AFKing deliveries across an
///         unadvanced calendar gap. Test-only storage reads use compiler-derived packed offsets.
contract QuestStreakStallForgiveness is DeployProtocol {
    uint256 private constant QUEST_STATE_SLOT = 1;
    uint256 private constant QUEST_BITMAP_SLOT = 4;
    uint256 private constant OFF_LAST_ACTIVE = 3;
    uint256 private constant OFF_LAST_SYNC = 6;
    uint256 private constant OFF_STREAK = 9;
    uint256 private constant OFF_COMPLETION_MASK = 24;
    uint256 private constant OFF_SHIELD = 25;

    uint256 private constant GAME_HEADER_SLOT = 0;
    uint256 private constant OFF_DAILY_IDX = 3;
    uint256 private constant MINT_PACKED_SLOT = 9;
    uint256 private constant DEITY_SHIFT = 184;
    uint256 private constant SUB_OF_SLOT = 54;
    uint256 private constant OFF_SUB_SCORE = 5;
    uint256 private constant OFF_SUB_LAST_AUTO = 10;
    uint256 private constant OFF_SUB_COVERED = 16;
    uint256 private constant OFF_SUB_START = 19;
    uint256 private constant OFF_SUB_STREAK_BASE = 29;

    uint256 private constant MINT_PRICE = 0.5 ether;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 5_000_000 ether);
    }

    function test_ManualStreakForgivesOnlyUnrolledDays() public {
        address player = makeAddr("manual-gap");
        _roll(10);
        _award(player, 10, 10);
        _grantShields(player, 2);

        _roll(18); // days 11..17 had no rolled quest
        for (uint24 day = 11; day < 18; ++day) {
            assertFalse(_questWasRolled(day), "jump leaves every intervening day unrolled");
        }
        assertEq(quests.effectiveBaseStreak(player), 10, "unrolled days do not decay the streak view");
        assertEq(_questField(player, OFF_SHIELD, 8), 2, "unrolled days consume no shields");

        (, , uint32 streak, bool completed) = _completePrimary(player);
        assertTrue(completed, "next rolled primary completes");
        assertEq(streak, 11, "streak continues on the next playable quest");
        assertEq(_questField(player, OFF_SHIELD, 8), 2, "sync consumed no shield");
    }

    function test_RealAdvanceRecoveryBanksGapAndKeepsManualStreak() public {
        address player = makeAddr("real-advance-gap");
        _settleCurrentGameDay(0xA11CE);
        uint24 initialQuestDay = _activeQuestDay();
        assertEq(initialQuestDay, uint24(game.currentDayView()), "fixture landed the healthy daily quest");
        (, , uint32 initialStreak, bool initialCompleted) = _completePrimary(player);
        assertTrue(initialCompleted, "fixture completed the healthy primary");
        assertEq(initialStreak, 1, "fixture starts a one-day streak");

        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < 20 && !game.rngLocked(); ++i) game.advanceGame();
        assertTrue(game.rngLocked(), "daily request entered the stalled window");
        uint256 stalledRequest = mockVRF.lastRequestId();

        vm.warp(block.timestamp + 8 days);
        mockVRF.fulfillRandomWords(stalledRequest, 0xBACC_F111);
        uint24 recoveryDay = uint24(game.currentDayView());
        for (uint256 i; i < 40 && _activeQuestDay() != recoveryDay; ++i) game.advanceGame();

        assertEq(_activeQuestDay(), recoveryDay, "real rngGate recovery rolled only the wall-day quest");
        for (uint24 day = initialQuestDay + 1; day < recoveryDay; ++day) {
            assertFalse(_questWasRolled(day), "real recovery does not invent a quest for a gap day");
        }
        assertEq(quests.effectiveBaseStreak(player), 1, "real stalled days preserve the manual streak");
        (, , uint32 recoveredStreak, bool recoveredCompleted) = _completePrimary(player);
        assertTrue(recoveredCompleted, "recovery-day primary completes");
        assertEq(recoveredStreak, 2, "real recovery continues the streak");
    }

    function test_MixedGapConsumesShieldsOnlyForRolledMisses() public {
        address player = makeAddr("mixed-gap");
        _roll(10);
        _award(player, 10, 10);
        _grantShields(player, 3);

        _roll(15); // four unrolled days: 11..14
        _roll(16); // rolled and genuinely missed: 15
        _roll(17); // rolled and genuinely missed: 16
        _roll(18); // rolled and genuinely missed: 17

        (, , uint32 streak, bool completed) = _completePrimary(player);
        assertTrue(completed, "current primary completes");
        assertFalse(_questWasRolled(14), "last skipped day remains unrolled");
        assertTrue(_questWasRolled(15), "recovery day is playable");
        assertEq(_questField(player, OFF_SHIELD, 8), 0, "three real misses consume three shields");
        assertEq(streak, 11, "covered real misses preserve the streak before the new completion");
    }

    function test_MidStallWallClockSyncCannotReopenCompletionOrMiscountGap() public {
        address completedPlayer = makeAddr("mask-player");
        address debtPlayer = makeAddr("debt-player");

        _roll(8);
        _award(debtPlayer, 5, 8);
        _roll(10); // bank day 9

        _award(completedPlayer, 5, 10);
        _completePrimary(completedPlayer);
        assertEq(_questField(completedPlayer, OFF_COMPLETION_MASK, 8) & 1, 1, "primary is complete");

        // Game-side callers pass wall time here during a stalled advance. They must synchronize
        // against the newest rolled quest day (10), not move the completion epoch to wall day 13.
        vm.prank(ContractAddresses.GAME);
        quests.beginAfking(completedPlayer, 13);
        assertEq(_questField(completedPlayer, OFF_LAST_SYNC, 24), 10, "sync clock stays on rolled day");
        assertEq(_questField(completedPlayer, OFF_COMPLETION_MASK, 8) & 1, 1, "completion mask stays closed");
        (, , , bool duplicate) = _completePrimary(completedPlayer);
        assertFalse(duplicate, "the same stale quest cannot pay twice");

        // This player has an older anchor. A wall-day bonus advances it only to quest day 10;
        // the rolled-day history then makes later gap accounting independent of wall time.
        _award(debtPlayer, 4, 13);
        assertEq(_questField(debtPlayer, OFF_LAST_ACTIVE, 24), 10, "bonus anchor normalized to quest day");
        assertEq(_questField(debtPlayer, OFF_STREAK, 16), 9, "bonus reaches the raw streak");
        assertEq(quests.effectiveBaseStreak(debtPlayer), 5, "same-day view remains the start-of-day snapshot");

        _roll(16);
        assertFalse(_questWasRolled(15), "later gap day remains unrolled");
        assertEq(quests.effectiveBaseStreak(debtPlayer), 9, "recovery cannot panic or erase the bonus");
    }

    function test_FinalizeIgnoresUnrolledGapButNotNextRolledMiss() public {
        address player = makeAddr("finalize-unrolled");
        _roll(10);
        _award(player, 10, 10);
        _beginAfking(player, 10);

        _roll(16); // bank days 11..15 before finalization
        _finalizeAfking(player, 10, 10, 16);
        assertEq(_questField(player, OFF_STREAK, 16), 10, "unrolled gap preserves earned streak");
        assertEq(_questField(player, OFF_LAST_ACTIVE, 24), 10, "anchor remains the actual valid mint day");

        _roll(17);
        assertEq(quests.effectiveBaseStreak(player), 0, "rolled day 16 was a real miss and is not forgiven twice");
    }

    function test_FinalizePendingTailSurvivesRecoveryThenDecaysOnRealMiss() public {
        address player = makeAddr("finalize-tail");
        _roll(10);
        _award(player, 10, 10);
        _beginAfking(player, 10);

        _finalizeAfking(player, 10, 10, 13); // days 11 and 12 have no rolled quest yet
        assertEq(_questField(player, OFF_STREAK, 16), 10, "pending unrolled tail is forgiven");
        assertEq(_questField(player, OFF_LAST_ACTIVE, 24), 10, "future wall days are not stored as quest anchors");

        _roll(16); // days 11..15 remain unrolled
        assertEq(quests.effectiveBaseStreak(player), 10, "streak remains live on recovery day");
        _roll(17);
        assertEq(quests.effectiveBaseStreak(player), 0, "first genuinely missed rolled day still decays");
    }

    function test_FinalizeDeliveredAheadKeepsAnchorThroughRecovery() public {
        address player = makeAddr("finalize-ahead");
        _roll(10);
        _award(player, 10, 10);
        _beginAfking(player, 10);

        // The afking stage delivers pre-RNG, so coverage (13) leads the newest roll (10) at a
        // cancel inside the delivery->seal window. The delivered day must stay a valid anchor.
        _finalizeAfking(player, 10, 13, 13);
        assertEq(_questField(player, OFF_STREAK, 16), 10, "delivered-ahead finalize keeps the earned streak");
        assertEq(_questField(player, OFF_LAST_ACTIVE, 24), 13, "anchor stays at the delivered high-water");
        assertEq(_questField(player, OFF_SHIELD, 8), 0, "finalization creates no synthetic shield");

        _roll(13); // recovery roll lands ON the delivered day; 11 and 12 remain unrolled
        assertFalse(_questWasRolled(12), "pre-anchor gap day remains unrolled");
        assertTrue(_questWasRolled(13), "delivered anchor day later becomes playable");
        _roll(14);
        (, , uint32 streak, bool completed) = _completePrimary(player);
        assertTrue(completed, "next-day primary completes");
        assertEq(streak, 11, "the delivered day is not a phantom miss");
        assertEq(_questField(player, OFF_SHIELD, 8), 0, "no shield was needed or granted");
    }

    function test_FinalizeDeliveredAheadThenLaterStallNeedsNoSyntheticShield() public {
        address player = makeAddr("finalize-deficit");
        _roll(10);
        _award(player, 10, 10);
        _beginAfking(player, 10);
        _finalizeAfking(player, 10, 13, 13);

        // The anchor-day quest is covered even though it rolls after finalization. A later
        // jump has no rolled quests on days 14..16, so it needs no scalar correction.
        _roll(13);
        _roll(17);
        (, , uint32 streak, bool completed) = _completePrimary(player);
        assertTrue(completed, "post-second-stall primary completes");
        assertEq(streak, 11, "the rolled-day history preserves the streak exactly");
        assertEq(_questField(player, OFF_SHIELD, 8), 0, "no hidden compensation was consumed");
    }

    function test_FinalizeDeliveredAheadDoesNotLicenseRealMisses() public {
        address player = makeAddr("finalize-no-license");
        _roll(10);
        _award(player, 10, 10);
        _beginAfking(player, 10);
        _finalizeAfking(player, 10, 13, 13);

        // The anchor-day roll is covered, but rolled days 14 and 15 are genuine misses.
        _roll(13); // days 11 and 12 remain unrolled
        _roll(14);
        _roll(15);
        _roll(16); // rolled days 14 and 15 were really missed
        (, , uint32 streak, bool completed) = _completePrimary(player);
        assertTrue(completed, "day-16 primary completes");
        assertEq(streak, 1, "two real rolled misses reset the streak");
        assertEq(_questField(player, OFF_SHIELD, 8), 0, "finalization never licensed a miss");
    }

    function test_FinalizeDeliveredAheadLateRecoveryBanksExactly() public {
        address player = makeAddr("finalize-late-word");
        _roll(10);
        _award(player, 10, 10);
        _beginAfking(player, 10);

        // Word lands two days after the last delivery: the (13, 15) tail is forgiven at
        // finalize, and recovery banking past the anchor is credited exactly once.
        _finalizeAfking(player, 10, 13, 15);
        assertEq(_questField(player, OFF_STREAK, 16), 10, "unadvanced tail beyond coverage is forgiven");
        assertEq(_questField(player, OFF_LAST_ACTIVE, 24), 13, "anchor stays at the delivered high-water");

        _roll(16); // days 11..15 remain unrolled, including 14 and 15 after the anchor
        (, , uint32 streak, bool completed) = _completePrimary(player);
        assertTrue(completed, "recovery-day primary completes");
        assertEq(streak, 11, "post-anchor unrolled days are ignored exactly");
        assertEq(_questField(player, OFF_SHIELD, 8), 0, "no shield was minted");
    }

    function test_FinalizeAheadCyclesNeverGrantShields() public {
        address player = makeAddr("finalize-no-farm");
        _roll(10);
        _award(player, 10, 10);
        _beginAfking(player, 10);
        _finalizeAfking(player, 10, 13, 13);
        assertEq(_questField(player, OFF_SHIELD, 8), 0, "first ahead finalize grants no shield");

        // A later coverage-advancing cycle was the farmable path in the compensating-shield
        // workaround. Neither cycle may mutate the player's shield inventory.
        _beginAfking(player, 13);
        _finalizeAfking(player, 10, 14, 14);
        assertEq(_questField(player, OFF_SHIELD, 8), 0, "coverage advancement grants nothing");
        assertEq(_questField(player, OFF_LAST_ACTIVE, 24), 14, "anchor follows actual coverage");
    }

    function test_FinalizeStaleBankCannotForgiveRolledMisses() public {
        address player = makeAddr("finalize-stale-bank");
        _roll(10);
        _award(player, 10, 10); // activity anchor 10
        _beginAfking(player, 10);

        _roll(16); // days 11..15 were unrolled inside coverage already settled by the run
        _roll(17);
        _roll(18);
        _roll(19);
        _roll(20);
        _roll(21);
        _roll(22);

        // Coverage reached day 20; rolled days 21 and 22 were genuinely missed. The stale
        // five-day bank (all behind the coverage high-water) must not forgive them.
        _finalizeAfking(player, 20, 20, 23);
        assertEq(_questField(player, OFF_STREAK, 16), 0, "pre-coverage stalls cannot keep a lapsed run alive");
    }

    function test_GenesisConsecutiveAndJumpMarkOnlyRolledDays() public {
        _roll(10);
        assertTrue(_questWasRolled(10), "genesis quest day is marked");
        _roll(11);
        _roll(12);
        assertTrue(_questWasRolled(11), "consecutive day 11 is marked");
        assertTrue(_questWasRolled(12), "consecutive day 12 is marked");
        _roll(15);
        assertFalse(_questWasRolled(13), "skipped day 13 is not marked");
        assertFalse(_questWasRolled(14), "skipped day 14 is not marked");
        assertTrue(_questWasRolled(15), "jump destination is marked");
    }

    function test_RolledMissBitmapCountsAcrossWordBoundary() public {
        address player = makeAddr("bitmap-boundary");
        _roll(254);
        _award(player, 10, 254);
        _grantShields(player, 2);

        _roll(255); // high bit of bitmap word 0
        _roll(256); // low bit of bitmap word 1
        _roll(260); // days 257..259 were unrolled

        (, , uint32 streak, bool completed) = _completePrimary(player);
        assertTrue(completed, "current primary completes across bitmap boundary");
        assertEq(_questField(player, OFF_SHIELD, 8), 0, "only days 255 and 256 consume shields");
        assertEq(streak, 11, "unrolled days 257..259 do not affect the streak");
    }

    function test_MultipleStallsDoNotCrossCreditPastNewAnchor() public {
        address player = makeAddr("two-stalls");
        _roll(10);
        _award(player, 10, 10);
        _grantShields(player, 1);

        _roll(15); // bank 11..14
        _completePrimary(player); // new activity anchor on rolled day 15
        _roll(16); // rolled day 15 is complete; day 16 will be the real miss
        _roll(20); // bank 17..19

        (, , uint32 streak, bool completed) = _completePrimary(player);
        assertTrue(completed, "post-second-stall primary completes");
        assertEq(_questField(player, OFF_SHIELD, 8), 0, "only rolled day 16 consumes the shield");
        assertEq(streak, 12, "prior bank cannot be reused past the day-15 anchor");
    }

    function test_AfkingStageGapPreservesPreBuyScoreAndExactEarnedSpan() public {
        address player = _startAfkingPlayer("stage-gap", 10);
        uint24 startDay = uint24(game.currentDayView());
        uint256 snapshot = vm.snapshotState();

        vm.warp(block.timestamp + 1 days);
        _driveUntilDelivered(player);
        uint16 healthyScore = uint16(_subField(player, OFF_SUB_SCORE, 16));
        uint24 healthyCovered = uint24(_subField(player, OFF_SUB_COVERED, 24));
        uint24 healthyStart = uint24(_subField(player, OFF_SUB_START, 24));
        assertEq(healthyCovered - healthyStart, 1, "healthy delivery earns one funded day");

        vm.revertToState(snapshot);
        vm.warp(block.timestamp + 3 days);
        _driveUntilDelivered(player);
        uint16 gapScore = uint16(_subField(player, OFF_SUB_SCORE, 16));
        uint24 gapCovered = uint24(_subField(player, OFF_SUB_COVERED, 24));
        uint24 gapStart = uint24(_subField(player, OFF_SUB_START, 24));

        assertEq(gapScore, healthyScore, "score freezes the preserved pre-buy streak, not a false zero");
        assertEq(gapCovered - gapStart, 1, "phantom days do not inflate the earned span");
        assertEq(gapStart, startDay + 2, "two unadvanced days shift the run base forward");
        assertEq(_subField(player, OFF_SUB_STREAK_BASE, 16), 10, "streak base survives the gap");
    }

    function test_AfkingActiveResubscribeGapPreservesRun() public {
        address player = _startAfkingPlayer("resub-gap", 12);
        uint24 startDay = uint24(_subField(player, OFF_SUB_START, 24));
        vm.warp(block.timestamp + 3 days);

        vm.prank(player);
        game.subscribe(address(0), false, false, 1, address(0));

        uint24 covered = uint24(_subField(player, OFF_SUB_COVERED, 24));
        uint24 shiftedStart = uint24(_subField(player, OFF_SUB_START, 24));
        assertEq(covered, uint24(game.currentDayView()), "cover buy advances to the wall day");
        assertEq(shiftedStart, startDay + 2, "active re-subscribe excludes both phantom days");
        assertEq(covered - shiftedStart, 1, "re-subscribe adds exactly its funded delivery");
        assertEq(_subField(player, OFF_SUB_STREAK_BASE, 16), 12, "active run base is preserved");

        // A second retry-day cover composes from the already-shifted framing: only the new
        // intervening phantom day is excluded, and the second funded buy adds one more day.
        vm.warp(block.timestamp + 2 days);
        vm.prank(player);
        game.subscribe(address(0), false, false, 1, address(0));
        covered = uint24(_subField(player, OFF_SUB_COVERED, 24));
        shiftedStart = uint24(_subField(player, OFF_SUB_START, 24));
        assertEq(covered - shiftedStart, 2, "retry-day covers compose as two funded days");
        assertEq(_subField(player, OFF_SUB_STREAK_BASE, 16), 12, "base survives repeated pending-gap covers");
    }

    function test_AfkingGapDoesNotForgiveRealMissBeforeStall() public {
        address player = _startAfkingPlayer("real-before-gap", 12);
        uint24 coveredBefore = uint24(_subField(player, OFF_SUB_COVERED, 24));

        // Two sealed calendar days with no funded delivery precede the pending gap.
        _setDailyIdx(coveredBefore + 2);
        vm.warp(block.timestamp + 5 days);
        vm.prank(player);
        game.subscribe(address(0), false, false, 1, address(0));

        uint24 today = uint24(game.currentDayView());
        assertEq(_subField(player, OFF_SUB_STREAK_BASE, 16), 0, "real pre-stall miss re-bases the streak");
        assertEq(_subField(player, OFF_SUB_START, 24), today, "fresh run begins on the delivered day");
        assertEq(_subField(player, OFF_SUB_COVERED, 24), today, "delivery still advances coverage");
    }

    function test_LiveAfkingActivityScoreDoesNotDropDuringPendingGap() public {
        address player = _startAfkingPlayer("live-gap", 11);
        uint24 covered = uint24(_subField(player, OFF_SUB_COVERED, 24));
        _setSubU24(player, OFF_SUB_START, covered - 1); // one already-earned funded day

        uint256 beforeScore = game.playerActivityScore(player);
        vm.warp(block.timestamp + 3 days);
        uint256 duringGapScore = game.playerActivityScore(player);

        assertEq(duringGapScore, beforeScore, "unadvanced wall days do not temporarily zero the live AFKing streak");
    }

    function _roll(uint24 day) private {
        vm.prank(ContractAddresses.GAME);
        quests.rollDailyQuest(day, uint256(keccak256(abi.encode("stall-quest", day))) | 1, false, false);
    }

    function _award(address player, uint16 amount, uint24 wallDay) private {
        vm.prank(ContractAddresses.GAME);
        quests.awardQuestStreakBonus(player, amount, wallDay);
    }

    function _grantShields(address player, uint16 amount) private {
        vm.prank(ContractAddresses.GAME);
        quests.awardQuestStreakShield(player, amount);
    }

    function _beginAfking(address player, uint24 wallDay) private {
        vm.prank(ContractAddresses.GAME);
        quests.beginAfking(player, wallDay);
    }

    function _finalizeAfking(address player, uint24 earned, uint24 covered, uint24 wallDay) private {
        vm.prank(ContractAddresses.GAME);
        quests.finalizeAfking(player, earned, covered, wallDay);
    }

    function _completePrimary(address player)
        private
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
    {
        vm.prank(ContractAddresses.COIN);
        return quests.handleMint(player, 1, true, MINT_PRICE);
    }

    function _startAfkingPlayer(string memory label, uint16 streak) private returns (address player) {
        player = makeAddr(label);
        uint24 today = uint24(game.currentDayView());
        _roll(today);
        _award(player, streak, today);
        _grantDeityPass(player);
        vm.deal(address(this), 50 ether);
        game.depositAfkingFunding{value: 50 ether}(player);
        vm.prank(player);
        game.subscribe(address(0), false, false, 1, address(0));
        assertEq(_subField(player, OFF_SUB_COVERED, 24), today, "fixture cover buy grounds current day");
    }

    function _driveUntilDelivered(address player) private {
        uint24 today = uint24(game.currentDayView());
        for (uint256 i; i < 20 && _subField(player, OFF_SUB_LAST_AUTO, 24) != today; ++i) {
            game.advanceGame();
        }
        assertEq(_subField(player, OFF_SUB_LAST_AUTO, 24), today, "subscriber stage delivered current day");
    }

    function _settleCurrentGameDay(uint256 word) private {
        for (uint256 i; i < 120; ++i) {
            _fulfillLatest(word);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.advanceGame();
            _fulfillLatest(word);
        }
        revert("fixture failed to settle current game day");
    }

    function _fulfillLatest(uint256 word) private {
        uint256 requestId = mockVRF.lastRequestId();
        if (requestId == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(requestId);
        if (!fulfilled) mockVRF.fulfillRandomWords(requestId, word);
    }

    function _activeQuestDay() private view returns (uint24) {
        return uint24(uint256(vm.load(address(quests), bytes32(0))));
    }

    function _grantDeityPass(address player) private {
        bytes32 slot = keccak256(abi.encode(player, MINT_PACKED_SLOT));
        uint256 packed = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(packed | (uint256(1) << DEITY_SHIFT)));
    }

    function _questWord(address player) private view returns (uint256) {
        return uint256(vm.load(address(quests), keccak256(abi.encode(player, QUEST_STATE_SLOT))));
    }

    function _questField(address player, uint256 offset, uint256 width) private view returns (uint256) {
        return (_questWord(player) >> (offset * 8)) & ((uint256(1) << width) - 1);
    }

    function _questWasRolled(uint24 day) private view returns (bool) {
        bytes32 slot = keccak256(abi.encode(uint16(day >> 8), QUEST_BITMAP_SLOT));
        return (uint256(vm.load(address(quests), slot)) & (uint256(1) << uint8(day))) != 0;
    }

    function _subSlot(address player) private pure returns (bytes32) {
        return keccak256(abi.encode(player, SUB_OF_SLOT));
    }

    function _subField(address player, uint256 offset, uint256 width) private view returns (uint256) {
        uint256 packed = uint256(vm.load(address(game), _subSlot(player)));
        return (packed >> (offset * 8)) & ((uint256(1) << width) - 1);
    }

    function _setSubU24(address player, uint256 offset, uint24 value) private {
        bytes32 slot = _subSlot(player);
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 shift = offset * 8;
        packed = (packed & ~(uint256(type(uint24).max) << shift)) | (uint256(value) << shift);
        vm.store(address(game), slot, bytes32(packed));
    }

    function _setDailyIdx(uint24 value) private {
        uint256 packed = uint256(vm.load(address(game), bytes32(GAME_HEADER_SLOT)));
        uint256 shift = OFF_DAILY_IDX * 8;
        packed = (packed & ~(uint256(type(uint24).max) << shift)) | (uint256(value) << shift);
        vm.store(address(game), bytes32(GAME_HEADER_SLOT), bytes32(packed));
    }
}
