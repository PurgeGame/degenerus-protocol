// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {QaSlots} from "../helpers/QaSlots.sol";

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {activityScoreOf} from "../helpers/ActivityScoreOf.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title QuestStreakStallForgiveness
/// @notice Regression coverage for logical quest days and AFKing deliveries across an
///         unadvanced calendar gap. Test-only storage reads use compiler-derived packed offsets.
contract QuestStreakStallForgiveness is DeployProtocol {
    uint256 private constant QUEST_STATE_SLOT = QaSlots.STATE;
    uint256 private constant OFF_LAST_ACTIVE = 3;
    uint256 private constant OFF_LAST_SYNC = 6;
    uint256 private constant OFF_STREAK = 9;
    uint256 private constant OFF_COMPLETION_MASK = 24;
    uint256 private constant OFF_SHIELD = 25;

    uint256 private constant GAME_HEADER_SLOT = 0;
    uint256 private constant OFF_DAILY_IDX = 3;
    // Member lane: score code 36-45, checkpoint day 46-67, checkpoint streak 69-84.
    uint256 private constant LANE_SCORE_SHIFT = 36;
    uint256 private constant LANE_DAY_SHIFT = 46;
    uint256 private constant LANE_STREAK_SHIFT = 69;

    uint256 private constant MINT_PRICE = 0.5 ether;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 1_000 ether);
        vm.deal(address(game), 5_000_000 ether);
    }

    function test_CalendarStallPreservesStreakAndShields() public {
        address player = makeAddr("calendar-stall");
        _roll(10); _award(player, 10, 10); _grantShields(player, 2);
        uint256 beforeStreak = quests.effectiveBaseStreak(_qid(player));
        vm.warp(block.timestamp + 8 days);
        assertEq(game.currentDayView_g542950(), 10);
        assertEq(quests.effectiveBaseStreak(_qid(player)), beforeStreak);
        assertEq(_questField(player, OFF_STREAK, 16), 10);
        assertEq(_questField(player, OFF_SHIELD, 8), 2);
        _roll(11);
        (,,uint32 streak,bool completed) = _completePrimary(player);
        assertTrue(completed); assertEq(streak, 11);
        assertEq(_questField(player, OFF_SHIELD, 8), 2);
    }

    function test_MissedLogicalDaysConsumeShieldsExactlyOnce() public {
        address player = makeAddr("logical-misses");
        _roll(10); _award(player, 10, 10); _grantShields(player, 3);
        _roll(14); // Three actually requested logical days were missed.
        (,,uint32 streak,bool completed) = _completePrimary(player);
        assertTrue(completed); assertEq(streak, 11);
        assertEq(_questField(player, OFF_SHIELD, 8), 0);
        (,,,bool duplicate) = _completePrimary(player);
        assertFalse(duplicate);
    }

    function test_NoBitmapForgivenessForMissedLogicalDays() public {
        address player = makeAddr("unrolled-is-not-a-calendar-gap");
        _roll(10); _award(player, 10, 10); _grantShields(player, 2);
        _roll(18);
        assertEq(quests.effectiveBaseStreak(_qid(player)), 0);
        (,,uint32 streak,bool completed) = _completePrimary(player);
        assertTrue(completed); assertEq(streak, 1);
        assertEq(_questField(player, OFF_SHIELD, 8), 0);
    }

    function test_CalendarSyncCannotReopenCompletedQuest() public {
        address player = makeAddr("completion-mask");
        _roll(10); _award(player, 5, 10); _completePrimary(player);
        vm.warp(block.timestamp + 8 days);
        _beginAfking(player, 10);
        assertEq(_questField(player, OFF_LAST_SYNC, 24), 10);
        assertEq(_questField(player, OFF_COMPLETION_MASK, 8) & 1, 1);
        (,,,bool duplicate) = _completePrimary(player); assertFalse(duplicate);
    }

    function test_FinalizeCalendarTailPreservesOnlyDeliveredAnchor() public {
        address player = makeAddr("finalize-calendar-tail");
        _roll(10); _award(player, 10, 10); _beginAfking(player, 10);
        vm.warp(block.timestamp + 8 days);
        _finalizeAfking(player, 10, 10);
        assertEq(_questField(player, OFF_STREAK, 16), 10);
        assertEq(_questField(player, OFF_LAST_ACTIVE, 24), 10);
        _roll(11); assertEq(quests.effectiveBaseStreak(_qid(player)), 10);
        _roll(12); assertEq(quests.effectiveBaseStreak(_qid(player)), 0);
    }

    function test_FinalizeDeliveredAheadRetainsPreRequestCoverage() public {
        address player = makeAddr("delivered-ahead");
        _roll(10); _award(player, 10, 10); _beginAfking(player, 10);
        _finalizeAfking(player, 11, 11);
        assertEq(_questField(player, OFF_LAST_ACTIVE, 24), 11);
        assertEq(_questField(player, OFF_SHIELD, 8), 0);
        _roll(11); _roll(12);
        (,,uint32 streak,bool completed) = _completePrimary(player);
        assertTrue(completed); assertEq(streak, 12);
        _finalizeAfking(player, 999, 999);
        assertEq(_questField(player, OFF_STREAK, 16), 12, "finalize is idempotent");
    }

    function test_LogicalMissesAcrossFormerBitmapBoundary() public {
        address player = makeAddr("boundary");
        _roll(254); _award(player, 10, 254); _grantShields(player, 2);
        _roll(257);
        (,,uint32 streak,bool completed) = _completePrimary(player);
        assertTrue(completed); assertEq(streak, 11);
        assertEq(_questField(player, OFF_SHIELD, 8), 0);
        _roll(259); assertEq(quests.effectiveBaseStreak(_qid(player)), 0);
    }

    function test_MultipleCalendarStallsDoNotManufactureStreakCredit() public {
        address player = makeAddr("multiple-stalls");
        _roll(10); _award(player, 10, 10);
        vm.warp(block.timestamp + 3 days); _roll(11); _completePrimary(player);
        vm.warp(block.timestamp + 4 days); _roll(12);
        (,,uint32 streak,bool completed) = _completePrimary(player);
        assertTrue(completed); assertEq(streak, 12);
        assertEq(_questField(player, OFF_SHIELD, 8), 0);
    }

    function test_RealDelayedRequestRetainsQuestAndStreakIdentity() public {
        address player = makeAddr("real-delay");
        uint24 initial = game.currentDayView_g542950();
        _award(player, 10, initial);
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < 100 && !game.rngLocked(); ++i) game.mineRun(0);
        assertTrue(game.rngLocked());
        uint24 requested = game.currentDayView_g542950();
        assertEq(requested, initial + 1);
        uint256 request = mockVRF.lastRequestId();
        vm.warp(block.timestamp + 8 days);
        assertEq(game.currentDayView_g542950(), requested);
        mockVRF.fulfillRandomWords(request, 0xBACC_F111);
        for (uint256 i; i < 100 && _activeQuestDay() != requested; ++i) game.mineRun(0);
        assertEq(_activeQuestDay(), requested);
        (,,uint32 streak,bool completed) = _completePrimary(player);
        assertTrue(completed); assertEq(streak, 11);
    }

    function test_AfkingCalendarGapDeliversOneLogicalDay() public {
        address player = _startAfkingPlayer("afking-calendar-gap", 10);
        uint24 start = game.currentDayView_g542950();
        uint256 beforeScore = activityScoreOf(address(game), player);
        vm.warp(block.timestamp + 3 days);
        assertEq(activityScoreOf(address(game), player), beforeScore);
        assertEq(_endpoint(), start);
        _driveUntilDelivered(player);
        assertEq(_endpoint(), start + 1);
        uint32[] memory ids = new uint32[](1); ids[0] = game.walletIdOf_g3120(player);
        game.claimAfkingFlip(ids);
        assertEq(_laneField(player, LANE_DAY_SHIFT, 22), start + 1);
        assertEq(_laneField(player, LANE_STREAK_SHIFT, 16), 11);
    }

    function _qid(address who) private returns (uint32 id) {
        id = game.walletIdOf_g3120(who);
        if (id == 0) id = _giveWalletId(who);
    }

    function _roll(uint24 day) private {
        _setDailyIdx(day);
        uint256 packed = uint256(vm.load(address(coinflip), bytes32(uint256(4))));
        vm.store(address(coinflip), bytes32(uint256(4)), bytes32((packed & ~(uint256(0xffffff) << 176)) | (uint256(day) << 176)));
        vm.prank(ContractAddresses.GAME);
        quests.rollDailyQuest(day, uint256(keccak256(abi.encode("stall-quest", day))) | 1, false, false, false);
    }

    function _award(address player, uint16 amount, uint24 wallDay) private {
        uint32 qid2 = _qid(player);
        vm.prank(ContractAddresses.GAME);
        quests.awardQuestStreakBonus(qid2, amount, wallDay);
    }

    function _grantShields(address player, uint16 amount) private {
        uint32 qid3 = _qid(player);
        vm.prank(ContractAddresses.GAME);
        quests.awardQuestStreakShield(qid3, amount);
    }

    function _beginAfking(address player, uint24 wallDay) private {
        uint32 qid4 = _qid(player);
        vm.prank(ContractAddresses.GAME);
        quests.beginAfking(qid4, wallDay);
    }

    function _finalizeAfking(address player, uint24 earned, uint24 covered) private {
        uint32 qid5 = _qid(player);
        vm.prank(ContractAddresses.GAME);
        quests.finalizeAfking(qid5, earned, covered);
    }

    function _completePrimary(address player)
        private
        returns (uint256 reward, uint8 questType, uint32 streak, bool completed)
    {
        uint32 qid6 = _qid(player);
        vm.prank(ContractAddresses.COIN);
        (reward, questType, streak, completed, ) = quests.handlePurchase_g23478(_fixtureGameDay(), qid6, MINT_PRICE, 0, 0, MINT_PRICE, MINT_PRICE);
    }

    function _startAfkingPlayer(string memory label, uint16 streak) private returns (address player) {
        player = makeAddr(label);
        uint24 today = uint24(game.currentDayView_g542950());
        _roll(today);
        _award(player, streak, today);
        uint256 seat = _grantSeat(player);
        uint32 id = game.walletIdOf_g3120(player);
        if (id == 0) id = _giveWalletId(player);
        vm.deal(address(this), 50 ether);
        game.depositAfkingFunding{value: 50 ether}(id);
        vm.prank(player);
        game.subscribe(0, false, 1, seat);
        assertEq(_laneField(player, LANE_DAY_SHIFT, 22), today, "the run is checkpointed on the signup day");
    }

    function _driveUntilDelivered(address) private {
        uint24 today = uint24(game.currentDayView_g542950()) + 1;
        for (uint256 i; i < 200 && _endpoint() != today; ++i) {
            _fulfillLatest(uint256(keccak256(abi.encode("drive", i))) | 1);
            game.mineRun(0);
        }
        assertEq(_endpoint(), today, "subscriber pass completed the current day");
    }

    function _settleCurrentGameDay(uint256 word) private {
        for (uint256 i; i < 120; ++i) {
            _fulfillLatest(word);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.mineRun(0);
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
        return uint24(uint256(vm.load(address(quests), bytes32(uint256(QaSlots.ACTIVE)))));
    }

    function _questWord(address player) private view returns (uint256) {
        return uint256(vm.load(address(quests), keccak256(abi.encode(uint256(game.walletIdOf_g3120(player)), QUEST_STATE_SLOT))));
    }

    function _questField(address player, uint256 offset, uint256 width) private view returns (uint256) {
        return (_questWord(player) >> (offset * 8)) & ((uint256(1) << width) - 1);
    }

    function _laneField(address player, uint256 shift, uint256 width) private view returns (uint256) {
        (uint256 lane,) = GameSlotKeys.subLane(address(game), game.walletIdOf_g3120(player));
        return (lane >> shift) & ((uint256(1) << width) - 1);
    }

    function _endpoint() private view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(GameSlots.AFKING_ENDPOINT_DAY))) >> (8 * GameSlots.AFKING_ENDPOINT_DAY_OFFSET));
    }

    function _setDailyIdx(uint24 value) private {
        uint256 packed = uint256(vm.load(address(game), bytes32(GAME_HEADER_SLOT)));
        uint256 shift = OFF_DAILY_IDX * 8;
        packed = (packed & ~(uint256(type(uint24).max) << shift)) | (uint256(value) << shift);
        vm.store(address(game), bytes32(GAME_HEADER_SLOT), bytes32(packed));
    }
}
