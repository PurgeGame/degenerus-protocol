// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm, VmSafe} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {PlayerQuestView} from "../../contracts/interfaces/IDegenerusQuests.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {CrapsPriceLib} from "../../contracts/libraries/CrapsPriceLib.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlotKeys} from "../helpers/GameSlots.sol";
import {QaSlots} from "../helpers/QaSlots.sol";

/// @title A paid future-day purchase finishes today's Craps join bonus
/// @notice Against the deployed table, FLIP and Quests: `buyFutureCrapsDays` reports a day pass and
///         a join from its one burn, so a wallet whose whole day is already seated (a prepaid
///         reservation or a comp) can finish today's "Join a Craps Battle" bonus by buying the next
///         day it may. The join counts once per purchase and only for today's quest; comps and
///         banked passes still report nothing; a rejected range reports nothing.
contract CrapsFutureDayJoinQuestTest is DeployProtocol {
    uint8 private constant QT_MINT_ETH = 1;
    uint8 private constant QT_DEG_ETH = 7;
    uint8 private constant QT_CRAPS_JOIN = 10;
    uint8 private constant QT_CRAPS_DAY_PASS = 11;
    uint8 private constant BONUS_SLOT = 1;
    uint32 private constant BOARD = 3 | (3 << 12) | (1 << 15);

    bytes4 private constant RECORD_CRAPS = bytes4(keccak256("recordCrapsAction_g14623(uint32,uint8)"));
    bytes32 private constant QUEST_COMPLETED = keccak256("QuestCompleted(uint32,uint24,uint8,uint8,uint32,uint256)");
    bytes32 private constant LEVEL_COMPLETED = keccak256("LevelQuestCompleted(uint32,uint24,uint8,uint256)");
    bytes32 private constant STREAK_BONUS = keccak256("QuestStreakBonusAwarded(uint32,uint16,uint24,uint24)");

    address private alice = makeAddr("future-join-alice");
    uint32 private id;
    uint256 private price;

    struct Report {
        uint256 calls; // recordCrapsAction calls
        uint8 flags; // the flags of the last one
        uint256 bonusDone; // QuestCompleted for today's join bonus
        uint256 bonusReward;
        uint256 primaryDone; // QuestCompleted for slot 0
        uint256 levelDone; // LevelQuestCompleted
        uint256 streakBonus; // QuestStreakBonusAwarded (the whole-day streak flags)
        uint256 burned; // FLIP leaving the buyer
    }

    function setUp() public {
        _deployProtocol();
        (,,,, price) = game.purchaseInfo_g1027();
        id = _giveWalletId(alice);
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame_g152734(alice, 50_000_000);
        vm.prank(ContractAddresses.CRAPS);
        coin.creditCrapsComps_g37225(1e12);
    }

    // ── fixture ──────────────────────────────────────────────────────────────

    function _active() private view returns (uint256) {
        return uint256(vm.load(address(quests), bytes32(QaSlots.ACTIVE)));
    }

    /// @dev Publish `day`'s quests (slot 0 MINT_ETH, slot 1 `bonusType`) and move the Game day,
    ///      which is both the table's today and the quest day, onto it.
    function _setDaily(uint24 day, uint8 bonusType) private {
        uint256 w = _active();
        uint256 rec0 = uint256(day) | (uint256(QT_MINT_ETH) << 24);
        uint256 rec1 = uint256(day) | (uint256(bonusType) << 24);
        vm.store(address(quests), bytes32(QaSlots.ACTIVE), bytes32((w & ~uint256(type(uint128).max)) | rec0 | (rec1 << 64)));
        _setRequestedFixtureDay(day);
        assertEq(crapsBattle.currentDayIndex(), day, "fixture: the table's today moved");
    }

    /// @dev Switch the level quest type and bump its version, as a roll does.
    function _setLevelQuest(uint8 qt) private {
        uint256 w = _active();
        uint256 version = uint24(w >> 136) + 1;
        w = (w & ~(uint256(0xffffffff) << 128)) | (uint256(qt) << 128) | ((version & 0xffffff) << 136);
        vm.store(address(quests), bytes32(QaSlots.ACTIVE), bytes32(w));
    }

    /// @dev A mint word passing the level-quest gates at the current level.
    function _levelEligible() private {
        uint256 lvl = game.currentLvl();
        uint256 w = ((lvl + 1) << BitPackingLib.LEVEL_UNITS_LEVEL_SHIFT) | (uint256(400) << BitPackingLib.LEVEL_UNITS_SHIFT)
            | (uint256(5) << BitPackingLib.LEVEL_STREAK_SHIFT) | ((lvl + 1) << BitPackingLib.MINT_STREAK_LAST_COMPLETED_SHIFT);
        vm.store(address(game), GameSlotKeys.mintPacked(id), bytes32(w));
    }

    /// @dev A funded mint of one ticket price on the live quest day: the primary.
    function _primary() private returns (Report memory r) {
        vm.recordLogs();
        vm.prank(address(game));
        quests.handlePurchase_g23478(_fixtureGameDay(), id, price, 0, 0, price, price);
        _grade(r, vm.getRecordedLogs());
    }

    /// @dev The scenario's starting point: on a day with no join bonus the wallet reserves the next
    ///      `reserved` days with FLIP; the next day is then today, wholly seated, with a join bonus.
    function _coveredToday(uint8 reserved) private returns (uint24 today) {
        uint24 d0 = crapsBattle.currentDayIndex();
        _setDaily(d0, QT_DEG_ETH);
        Report memory r = _buy(d0 + 1, reserved, false);
        assertEq(r.bonusDone, 0, "fixture: no join bonus on the reservation day");
        today = d0 + 1;
        _setDaily(today, QT_CRAPS_JOIN);
        assertTrue(crapsBattle.daySeatNumberOf(today, alice) != 0, "fixture: today is wholly seated");
        vm.expectRevert(CrapsBattleStorage.DayNotReservable.selector);
        vm.prank(alice);
        crapsBattle.buyFutureCrapsDays(today, 1, false, BOARD);
    }

    function _view() private view returns (PlayerQuestView memory) {
        return quests.getPlayerQuestView(id);
    }

    function _buy(uint24 start, uint8 count, bool high) private returns (Report memory r) {
        uint256 before = coin.balanceOf(alice);
        vm.recordLogs();
        vm.startStateDiffRecording();
        vm.prank(alice);
        crapsBattle.buyFutureCrapsDays(start, count, high, BOARD);
        _countReports(r, vm.stopAndReturnStateDiff());
        vm.stopMappingRecording();
        _grade(r, vm.getRecordedLogs());
        r.burned = before - coin.balanceOf(alice);
    }

    function _countReports(Report memory r, Vm.AccountAccess[] memory a) private view {
        for (uint256 i; i < a.length; ++i) {
            if (a[i].account != ContractAddresses.QUESTS || a[i].kind != VmSafe.AccountAccessKind.Call) continue;
            bytes memory d = a[i].data;
            if (d.length < 68 || bytes4(d) != RECORD_CRAPS) continue;
            uint32 who;
            uint8 flags;
            assembly ("memory-safe") {
                who := mload(add(d, 36))
                flags := mload(add(d, 68))
            }
            assertEq(who, id, "the report is keyed by the buyer's wallet ID");
            ++r.calls;
            r.flags = flags;
        }
    }

    function _grade(Report memory r, Vm.Log[] memory logs) private view {
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.emitter != address(quests) || l.topics.length == 0) continue;
            if (l.topics[0] == QUEST_COMPLETED && uint32(uint256(l.topics[1])) == id) {
                (uint8 qt,, uint256 reward) = abi.decode(l.data, (uint8, uint32, uint256));
                if (uint8(uint256(l.topics[3])) == BONUS_SLOT) {
                    assertEq(qt, QT_CRAPS_JOIN, "the bonus slot is the join quest");
                    ++r.bonusDone;
                    r.bonusReward += reward;
                } else {
                    ++r.primaryDone;
                }
            } else if (l.topics[0] == LEVEL_COMPLETED && uint32(uint256(l.topics[1])) == id) {
                ++r.levelDone;
            } else if (l.topics[0] == STREAK_BONUS && uint32(uint256(l.topics[1])) == id) {
                ++r.streakBonus;
            }
        }
    }

    function _assertBonusOpen(string memory why) private view {
        PlayerQuestView memory v = _view();
        assertFalse(v.completed[BONUS_SLOT], why);
        assertEq(v.progress[BONUS_SLOT], 0, why);
    }

    /// @dev What a purchase burns: the fixed price per day, plus the newcomer five percent this
    ///      fixture's fresh account pays — unchanged by the join report.
    function _cost(uint8 count, bool high) private pure returns (uint256 gross) {
        gross = uint256(count) * (high ? CrapsPriceLib.HIGH_RETAIL : CrapsPriceLib.NORMAL_RETAIL);
        gross += gross / 20;
    }

    // ── Case 1: today covered, primary done, buy tomorrow ────────────────────

    function _buyTomorrowFinishesTheBonusOnce(bool high) private {
        uint24 today = _coveredToday(1);
        assertEq(_primary().primaryDone, 1, "fixture: the primary completes");
        PlayerQuestView memory v = _view();
        assertTrue(v.completed[0], "fixture: primary done");
        _assertBonusOpen("fixture: bonus open");

        Report memory r = _buy(today + 1, 1, high);
        assertEq(r.calls, 1, "one report per purchase");
        assertEq(r.flags, 0x3, "PASS | JOIN, no streak flag, whatever the lane");
        assertEq(r.streakBonus, 0, "no whole-day streak credit from a future day");
        assertEq(r.bonusDone, 1, "today's join bonus completes");
        assertGt(r.bonusReward, 0, "and pays");
        assertEq(r.burned, _cost(1, high), "the price is unchanged");
        assertTrue(_view().completed[BONUS_SLOT], "bonus recorded complete");

        Report memory again = _buy(today + 2, 1, high);
        assertEq(again.calls, 1, "a repeat purchase still reports");
        assertEq(again.bonusDone, 0, "but completes nothing again");
    }

    function test_NormalFutureDayFinishesTodaysBonusOnce() public {
        _buyTomorrowFinishesTheBonusOnce(false);
    }

    function test_HighRollerFutureDayFinishesTodaysBonusOnce() public {
        _buyTomorrowFinishesTheBonusOnce(true);
    }

    // ── Case 2: tomorrow already reserved, buy the next available day ────────

    function test_TomorrowReservedTheNextAvailableDayQualifies() public {
        uint24 today = _coveredToday(2);
        assertTrue(crapsBattle.daySeatNumberOf(today + 1, alice) != 0, "fixture: tomorrow reserved");
        _primary();

        uint256 before = coin.balanceOf(alice);
        vm.expectRevert(CrapsBattleStorage.DayNotReservable.selector);
        vm.prank(alice);
        crapsBattle.buyFutureCrapsDays(today + 1, 1, false, BOARD);
        assertEq(coin.balanceOf(alice), before, "a rejected range burns nothing");
        _assertBonusOpen("a rejected range reports nothing");

        Report memory r = _buy(today + 2, 1, false);
        assertEq(r.bonusDone, 1, "the next available day finishes the bonus");

        // The last permitted day qualifies just the same on a fresh day.
        _setDaily(today + 1, QT_CRAPS_JOIN);
        _primary();
        r = _buy(today + 1 + 30, 1, false);
        assertEq(r.bonusDone, 1, "a reservation at the far edge qualifies");
    }

    // ── Case 3: before the primary, progress banks and completes as a pair ───

    function test_BeforeThePrimaryTheJoinBanksAndCompletesWithIt() public {
        uint24 today = _coveredToday(1);
        Report memory r = _buy(today + 1, 1, false);
        assertEq(r.bonusDone, 0, "a locked bonus does not complete on its own");
        PlayerQuestView memory v = _view();
        assertFalse(v.completed[BONUS_SLOT], "still open");
        assertGt(v.progress[BONUS_SLOT], 0, "the join is banked");

        Report memory p = _primary();
        assertEq(p.primaryDone, 1, "the primary completes");
        assertEq(p.bonusDone, 1, "and pulls the banked bonus with it");

        r = _buy(today + 2, 1, false);
        assertEq(r.bonusDone, 0, "no second completion");
    }

    // ── Multi-day: one action, one reward ────────────────────────────────────

    function test_MultiDayPurchaseIsOneQualifyingAction() public {
        uint24 today = _coveredToday(1);
        _primary();

        // From the same state, one day and three days finish the same bonus for the same reward.
        uint256 snap = vm.snapshotState();
        Report memory single = _buy(today + 1, 1, false);
        assertEq(single.bonusDone, 1);
        vm.revertToState(snap);

        Report memory r = _buy(today + 1, 3, false);
        assertEq(r.calls, 1, "one burn, one report");
        assertEq(r.flags, 0x3);
        assertEq(r.bonusDone, 1, "one completion");
        assertGt(r.bonusReward, 0);
        assertEq(r.bonusReward, single.bonusReward, "the reward is not multiplied by the day count");
        assertEq(r.burned, _cost(3, false), "three days at the fixed price");
        for (uint24 d = today + 1; d <= today + 3; ++d) {
            assertTrue(crapsBattle.daySeatNumberOf(d, alice) != 0, "every day in the run is seated");
        }
    }

    // ── Level quest: the day-pass credit stays and lands alongside ───────────

    function test_DayPassLevelCreditLandsWithTheJoinBonus() public {
        _setLevelQuest(QT_CRAPS_DAY_PASS);
        _levelEligible();
        uint24 today = _coveredToday(1);
        (uint8 qt,,, bool doneBefore, bool eligible) = quests.getPlayerLevelQuestView(id);
        assertEq(qt, QT_CRAPS_DAY_PASS, "fixture: day-pass level quest active");
        assertTrue(eligible, "fixture: eligible");
        assertTrue(doneBefore, "the reservation purchase already earned the level quest");

        // A fresh level quest (a new roll) for the purchase under test.
        _setLevelQuest(QT_CRAPS_DAY_PASS);
        _primary();
        Report memory r = _buy(today + 1, 1, false);
        assertEq(r.levelDone, 1, "the day-pass level quest completes");
        assertEq(r.bonusDone, 1, "and today's join bonus with it");
        (,,, bool doneAfter,) = quests.getPlayerLevelQuestView(id);
        assertTrue(doneAfter);
    }

    // ── What does not qualify ────────────────────────────────────────────────

    function test_CompAndBankedPassesDoNotQualify() public {
        uint24 today = _coveredToday(1);
        _primary();

        // A vault comp of future days: the comp lane pays and FLIP reports no action.
        uint256 code = uint256(id) | (uint256(2) << 160) | (uint256(today + 1) << 176) | (uint256(1) << 200);
        vm.recordLogs();
        vm.startStateDiffRecording();
        vm.prank(ContractAddresses.VAULT);
        crapsBattle.vaultComp(code);
        Report memory comp;
        _countReports(comp, vm.stopAndReturnStateDiff());
        vm.stopMappingRecording();
        _grade(comp, vm.getRecordedLogs());
        assertTrue(crapsBattle.daySeatNumberOf(today + 1, alice) != 0, "the comp seated the day");
        assertEq(comp.calls, 0, "a comp reports nothing");
        assertEq(comp.bonusDone, 0);
        _assertBonusOpen("a comp does not finish the bonus");

        // A banked pass committed to a future day: nothing is burned, nothing reported.
        vm.prank(address(game));
        crapsBattle.creditPasses(id, 1, 0);
        vm.recordLogs();
        vm.startStateDiffRecording();
        vm.prank(alice);
        crapsBattle.applyCrapsPasses(today + 2, 1, false, BOARD);
        Report memory pass;
        _countReports(pass, vm.stopAndReturnStateDiff());
        vm.stopMappingRecording();
        _grade(pass, vm.getRecordedLogs());
        assertTrue(crapsBattle.daySeatNumberOf(today + 2, alice) != 0, "the pass seated the day");
        assertEq(pass.calls, 0, "a banked pass reports nothing");
        _assertBonusOpen("a banked pass does not finish the bonus");

        // The paid purchase does.
        assertEq(_buy(today + 3, 1, false).bonusDone, 1);
    }

    function test_RejectedPurchasesReportNothing() public {
        uint24 today = _coveredToday(1);
        _primary();
        uint256 before = coin.balanceOf(alice);

        vm.startPrank(alice);
        vm.expectRevert(CrapsBattleStorage.DayNotReservable.selector);
        crapsBattle.buyFutureCrapsDays(today + 31, 1, false, BOARD);
        vm.expectRevert(CrapsBattleStorage.BadPassCount.selector);
        crapsBattle.buyFutureCrapsDays(today + 1, 0, false, BOARD);
        vm.expectRevert(CrapsBattleStorage.DayNotReservable.selector);
        crapsBattle.buyFutureCrapsDays(today + 30, 2, false, BOARD);
        vm.stopPrank();

        assertEq(coin.balanceOf(alice), before, "nothing burned");
        _assertBonusOpen("nothing reported");
        assertEq(_buy(today + 1, 1, false).bonusDone, 1, "a valid purchase then completes");
    }

    // ── A reservation never credits the reserved day's own quest ─────────────

    function test_TheReservedDayStartsWithItsBonusOpen() public {
        uint24 today = _coveredToday(1);
        _primary();
        assertEq(_buy(today + 1, 1, false).bonusDone, 1, "today's bonus finished");

        // Tomorrow arrives with its own join bonus: the reservation made yesterday did not
        // pre-credit it, and its primary alone does not pull it.
        _setDaily(today + 1, QT_CRAPS_JOIN);
        assertTrue(crapsBattle.daySeatNumberOf(today + 1, alice) != 0, "the reserved day is seated");
        _assertBonusOpen("the reserved day's bonus starts open");
        Report memory p = _primary();
        assertEq(p.primaryDone, 1);
        assertEq(p.bonusDone, 0, "nothing banked from the earlier purchase");

        assertEq(_buy(today + 2, 1, false).bonusDone, 1, "a purchase on this day finishes this day's bonus");
    }
}
