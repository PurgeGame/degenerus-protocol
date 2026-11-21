// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {PlayerQuestView} from "../../contracts/interfaces/IDegenerusQuests.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {GameSlotKeys} from "../helpers/GameSlots.sol";
import {QaSlots} from "../helpers/QaSlots.sol";

/// @notice Quest-streak sync rules on the deployed DegenerusQuests, driven through its gated
///         entry points as each caller reaches them:
///         - a foil purchase scores a streak above the floor as it stands;
///         - an afking handback is what the streak readers show on a day already synced;
///         - a zero streak spends no shield on missed days.
///         The fixture publishes quest days and Game days the way test/fuzz/QuestsWalletIds.t.sol
///         does.
contract QuestStreakSyncRulesTest is DeployProtocol {
    // DegenerusQuests roots (scripts/layout/golden/DegenerusQuests.json).
    uint256 private constant ACTIVE_ROOT = QaSlots.ACTIVE;
    uint256 private constant STATE_ROOT = QaSlots.STATE;
    uint256 private constant LEVEL_ROOT = QaSlots.LEVEL;
    // PlayerQuestState byte offsets.
    uint256 private constant OFF_LAST_ACTIVE = 3;
    uint256 private constant OFF_LAST_SYNC = 6;
    uint256 private constant OFF_STREAK = 9;
    uint256 private constant OFF_BASE_STREAK = 11;
    uint256 private constant OFF_MASK = 24;
    uint256 private constant OFF_SHIELD = 25;
    uint256 private constant OFF_AFKING_SINCE = 26;

    uint8 private constant QT_MINT_ETH = 1;
    uint8 private constant QT_DEG_ETH = 7;
    uint8 private constant QT_CRAPS_JOIN = 10;
    uint8 private constant QT_CRAPS_DAY_PASS = 11;

    uint8 private constant CRAPS_FLAG_JOIN = 0x1;
    uint8 private constant CRAPS_FLAG_PASS = 0x2;

    bytes32 private constant E_SHIELD_USED = keccak256("QuestStreakShieldUsed(uint32,uint16,uint16,uint24)");
    bytes32 private constant E_SHIELD_GRANTED = keccak256("QuestStreakShieldGranted(uint32,uint16,uint8)");
    bytes32 private constant E_BONUS = keccak256("QuestStreakBonusAwarded(uint32,uint16,uint24,uint24)");
    bytes32 private constant E_RESET = keccak256("QuestStreakReset(uint32,uint24,uint24)");

    uint256 private price;

    function setUp() public {
        _deployProtocol();
        (,,,, price) = game.purchaseInfo_g1027();
    }

    // =====================================================================
    // Helpers
    // =====================================================================

    function _stateSlot(uint32 id) private pure returns (bytes32) {
        return keccak256(abi.encode(uint256(id), STATE_ROOT));
    }

    function _qs(uint32 id) private view returns (uint256) {
        return uint256(vm.load(address(quests), _stateSlot(id)));
    }

    function _lq(uint32 id) private view returns (uint256) {
        return uint256(vm.load(address(quests), keccak256(abi.encode(uint256(id), LEVEL_ROOT))));
    }

    function _field(uint32 id, uint256 offset, uint256 width) private view returns (uint256) {
        return (_qs(id) >> (offset * 8)) & ((uint256(1) << width) - 1);
    }

    function _active() private view returns (uint256) {
        return uint256(vm.load(address(quests), bytes32(ACTIVE_ROOT)));
    }

    function _questDay() private view returns (uint24) {
        return uint24(_active());
    }

    /// @dev Switch the level quest type and bump its version, as a roll does.
    function _setLevelQuest(uint8 qt) private {
        uint256 w = _active();
        uint256 version = uint24(w >> 136) + 1;
        w = (w & ~(uint256(0xffffffff) << 128)) | (uint256(qt) << 128) | ((version & 0xffffff) << 136);
        vm.store(address(quests), bytes32(ACTIVE_ROOT), bytes32(w));
    }

    /// @dev Publish `day` with slot 0 MINT_ETH and slot 1 `slot1Type`, and advance the logical day
    ///      (Game header and Coinflip mirror).
    function _setDaily(uint24 day, uint8 slot1Type) private {
        uint256 w = _active();
        uint256 rec0 = uint256(day) | (uint256(QT_MINT_ETH) << 24);
        uint256 rec1 = uint256(day) | (uint256(slot1Type) << 24);
        w = (w & ~uint256(type(uint128).max)) | rec0 | (rec1 << 64);
        vm.store(address(quests), bytes32(ACTIVE_ROOT), bytes32(w));
        _setRequestedFixtureDay(day);
    }

    /// @dev The daily request for `day`: the Game day advances, the quest record stays on the
    ///      previous day until the roll.
    function _requestOnly(uint24 day) private {
        _setRequestedFixtureDay(day);
        assertEq(_questDay(), day - 1, "fixture: quests still on the previous day");
        assertEq(game.currentDayView_g542950(), day, "fixture: the Game day advanced");
    }

    /// @dev A mint word passing the level-quest gates at the current level (400 units at
    ///      level + 1) with a level streak of 5.
    function _eligible(address key) private {
        uint256 w = (uint256(game.currentLvl() + 1) << BitPackingLib.LEVEL_UNITS_LEVEL_SHIFT)
            | (uint256(400) << BitPackingLib.LEVEL_UNITS_SHIFT)
            | (uint256(5) << BitPackingLib.LEVEL_STREAK_SHIFT)
            | (uint256(game.currentLvl() + 1) << BitPackingLib.MINT_STREAK_LAST_COMPLETED_SHIFT);
        vm.store(address(game), GameSlotKeys.mintPacked(key), bytes32(w));
    }

    /// @dev Call Quests as `caller`, bubbling any revert.
    function _as(address caller, bytes memory data) private returns (bytes memory ret) {
        vm.prank(caller);
        bool ok;
        (ok, ret) = address(quests).call(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 32), mload(ret))
            }
        }
    }

    /// @dev A funded mint of one ticket price on the live quest day: completes the primary.
    function _primary(uint32 id) private {
        _as(
            address(game),
            abi.encodeCall(quests.handlePurchase_g23478, (_fixtureGameDay(), id, price, 0, 0, price, price))
        );
    }

    /// @dev A flip stake far below any target: runs the day's sync and completes nothing.
    function _touch(uint32 id) private {
        _as(address(coinflip), abi.encodeCall(quests.handleFlip_g217, (id, 1, _fixtureGameDay())));
    }

    function _bonus(uint32 id, uint16 amount) private {
        _as(address(game), abi.encodeCall(quests.awardQuestStreakBonus, (id, amount, _fixtureGameDay())));
    }

    /// @dev The foil handler as the Game calls it for a pack of ten ticket prices; returns the
    ///      score-basis streak, which is at least the foil floor of 12.
    function _foil(uint32 id) private returns (uint32 snapshot) {
        bytes memory ret =
            _as(address(game), abi.encodeCall(quests.handleFoilPurchase, (id, price * 10, 0, 0, price, price)));
        (,,, snapshot,) = abi.decode(ret, (uint256, uint8, bool, uint32, bool));
    }

    function _craps(uint32 id, uint8 flags) private {
        _as(address(coin), abi.encodeCall(quests.recordCrapsAction_g14623, (id, flags)));
    }

    function _countTopic(Vm.Log[] memory logs, bytes32 t0, uint32 id) private view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.emitter != address(quests) || l.topics.length < 2 || l.topics[0] != t0) continue;
            assertEq(uint256(l.topics[1]), uint256(id), "event subject is the wallet ID");
            ++n;
        }
    }

    // =====================================================================
    // Foil score basis on a live quest day
    // =====================================================================

    /// @dev A streak below the floor scores the floor: the pack raises its score basis to 12.
    function test_FoilScoreBasisBelowTheFloorIsTheFloor() public {
        uint32 id = _giveWalletId(makeAddr("foilBelowFloor"));
        _setDaily(20, QT_DEG_ETH);
        _bonus(id, 3);

        assertEq(_foil(id), 12, "the score basis is the streak raised to the floor");
        assertGe(_field(id, OFF_STREAK, 16), 12, "floored");
    }

    /// @dev A streak above the floor is the score basis as it stands: the floor never lowers or
    ///      raises it, and the stored streak keeps its value.
    function test_FoilScoreBasisAboveTheFloorIsTheStreakItself() public {
        uint32 id = _giveWalletId(makeAddr("foilAboveFloor"));
        _setDaily(20, QT_DEG_ETH);
        _bonus(id, 20);
        _setDaily(21, QT_DEG_ETH); // the next day: day 21's snapshot carries the bonus

        assertEq(_foil(id), 20, "a streak above the floor is the score basis unchanged");
        assertGe(_field(id, OFF_STREAK, 16), 20, "the floor never lowers a higher streak");
    }

    // =====================================================================
    // Afking handback on a day already synced
    // =====================================================================

    /// @dev A run that ends on a day the account already synced hands its streak to the streak
    ///      readers at once, on a later day of the run and on its start day alike.
    function test_FinalizeAfkingHandsTheStreakToTheDaySnapshot() public {
        uint32 id = _giveWalletId(makeAddr("handbackLaterDay"));
        _setDaily(20, QT_DEG_ETH);
        _as(address(game), abi.encodeCall(quests.beginAfking, (id, 20)));
        _setDaily(21, QT_DEG_ETH);
        _touch(id); // syncs day 21 while the manual streak is dormant at zero
        assertEq(_field(id, OFF_LAST_SYNC, 24), 21);
        assertEq(_field(id, OFF_BASE_STREAK, 16), 0);

        _as(address(game), abi.encodeCall(quests.finalizeAfking, (id, 200, 21)));
        assertEq(_field(id, OFF_STREAK, 16), 200, "handed back");
        assertEq(quests.effectiveBaseStreak(id), 200, "readers see the handback the same day");
        (uint32 eff, bool afk) = quests.effectiveBaseStreakAndAfking_g1521(id, 21);
        assertEq(eff, 200, "the Game-side read agrees");
        assertFalse(afk);
        PlayerQuestView memory v = quests.getPlayerQuestView(id);
        assertEq(v.baseStreak, 200, "the view agrees");
        _setDaily(22, QT_DEG_ETH);
        assertEq(quests.effectiveBaseStreak(id), 200, "and the next day");

        // Start day: beginAfking syncs the day on the pre-run streak; the handback replaces it.
        uint32 sid = _giveWalletId(makeAddr("handbackStartDay"));
        _as(address(game), abi.encodeCall(quests.beginAfking, (sid, 22)));
        assertEq(_field(sid, OFF_LAST_SYNC, 24), 22);
        _as(address(game), abi.encodeCall(quests.finalizeAfking, (sid, 6, 22)));
        assertEq(quests.effectiveBaseStreak(sid), 6, "start-day handback shows at once");
    }

    // =====================================================================
    // Shields and a zero streak
    // =====================================================================

    /// @dev Missed days spend no shield while the streak is zero and are not billed again later;
    ///      once a streak exists, a miss spends one shield as before.
    function test_ZeroStreakSpendsNoShieldOnMissedDays() public {
        uint32 id = _giveWalletId(makeAddr("zeroStreakShields"));
        _setDaily(10, QT_DEG_ETH);
        _primary(id); // streak 1, anchor day 10
        _setDaily(13, QT_DEG_ETH);
        _touch(id); // days 11 and 12 missed with no shield: reset
        assertEq(_field(id, OFF_STREAK, 16), 0, "fixture: the streak lapsed");
        _as(address(game), abi.encodeCall(quests.awardQuestStreakShield, (id, 3)));
        _setDaily(16, QT_DEG_ETH);

        vm.recordLogs();
        _touch(id); // days 13 to 15 missed on a zero streak
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_field(id, OFF_LAST_SYNC, 24), 16, "synced");
        assertEq(_field(id, OFF_SHIELD, 8), 3, "a zero streak spends no shield");
        assertEq(_countTopic(logs, E_SHIELD_USED, id), 0);
        assertEq(_countTopic(logs, E_RESET, id), 0);

        _primary(id); // day 16: streak 1, anchor day 16
        assertEq(_field(id, OFF_STREAK, 16), 1);
        assertEq(_field(id, OFF_SHIELD, 8), 3, "the earlier misses are not billed again");
        _setDaily(18, QT_DEG_ETH);

        vm.recordLogs();
        _primary(id); // day 17 missed on a live streak
        logs = vm.getRecordedLogs();
        assertEq(_countTopic(logs, E_SHIELD_USED, id), 1, "one shield for the one miss");
        assertEq(_field(id, OFF_SHIELD, 8), 2);
        assertEq(_field(id, OFF_STREAK, 16), 2, "streak kept and credited");
    }
}
