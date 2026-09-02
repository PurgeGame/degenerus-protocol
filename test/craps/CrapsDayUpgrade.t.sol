// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {LootboxCraps} from "../../contracts/LootboxCraps.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {CrapsPins} from "./CrapsPins.sol";

/// @dev The one internal the suite needs beyond the shared views: a DAY ticket's unscaled run at
///      a named window. `_slotWindow` refuses a day ticket's own remainder-zero slot, so the
///      window has to be supplied — which is exactly how settlement reads it too.
contract UpgradeHarness is CrapsViews {
    function dayRunAt(uint256 betId, uint64 slot) external view returns (uint256 won, uint256 paid) {
        Settlement memory s =
            _settlementOf(betId, _bets[betId], _slotWindow(slot), _wordAt(_indexOf(slot)));
        return (s.won, s.paid);
    }
}

/// @title Per-window high-roller upgrades of a whole-day ticket
/// @notice A normal day ticket already holds one copy of every window's run. An upgrade buys the
///         MISSING `H - 1` copies of chosen windows — bankroll and bounty alike — so the selected
///         window settles exactly as a native high seat: the same board, dice and rounding, paid
///         `H` times over, one main entry, one main bounty, `H - 1` in the lane.
///
/// @dev What these fixtures hold down:
///        - the delta is priced off each window's OWN terms and the day's OWN multiple;
///        - a batch is all or nothing over its NEW bits, and an already-high bit is never
///          charged again;
///        - the upgraded window and only the upgraded window joins the high lane;
///        - a native whole-day high seat and a normal seat upgraded window by window are the
///          same seat, to the wei, in payment and in the action books.
contract CrapsDayUpgradeTest is CrapsPins {
    UpgradeHarness internal craps;

    uint256 internal constant PLAIN_WORD = 40 << 8;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal dave = makeAddr("dave");

    /// @dev Local restatement for `expectEmit`; matched by topics, not by declaring contract.
    event CrapsDayWindowsUpgraded(
        address indexed player, uint24 indexed day, uint8 upgradedMask, uint256 burned
    );

    function setUp() public {
        _installPins();
        craps = new UpgradeHarness();
        // The deployment day is a Craps warm-up day with no windows; every fixture plays
        // from genesis + 1, the first day the table opens.
        vm.warp(block.timestamp + 1 days);
        _setIndex(4);
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
        uint256 floor_ = craps.SYBIL_SCORE_FLOOR();
        game.setScore(alice, floor_);
        game.setScore(bob, floor_);
        game.setScore(dave, floor_);
    }

    // ── fixtures ────────────────────────────────────────────────────────────

    /// @dev To the top of a protocol day, where period zero — the whole-day lane — is live.
    function _warpToDayStart() internal {
        uint256 elapsed = (vm.getBlockTimestamp() - 82_620) % 1 days;
        if (elapsed != 0) vm.warp(vm.getBlockTimestamp() + (1 days - elapsed));
    }

    /// @dev A day word whose high draw lands on `want`. Searched rather than named: the
    ///      derivation is a hash, so a literal would be a magic number nobody could check.
    function _wordFor(uint256 want) internal view returns (uint256) {
        for (uint256 i = 1; i < 500; ++i) {
            uint256 w = uint256(keccak256(abi.encode("up", i)));
            if (craps.highMultOfWord(w) == want) return w;
        }
        revert("no word draws that multiple");
    }

    /// @dev Open today at multiple `mult`, standing at the day's own start.
    function _openDay(uint256 mult) internal returns (uint24 day) {
        _warpToDayStart();
        day = craps.currentDayIndex();
        _setDailyWord(day, _wordFor(mult));
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
    }

    /// @dev One NORMAL whole-day ticket for `who`, blank board, bought in period zero.
    function _buyNormalDay(address who) internal {
        Craps.Bets memory blank;
        vm.prank(who);
        craps.enterBonusDay(blank, 1);
    }

    function _slotAt(uint24 day, uint256 period) internal view returns (uint64) {
        return uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + period + 1);
    }

    /// @dev What one window's upgrade must cost at multiple `mult`.
    function _deltaOf(uint24 day, uint256 period, uint256 mult) internal view returns (uint256) {
        (uint128 bank,,, uint256 bounty,,) = craps.bonusTermsFor(day, period);
        return (uint256(bank) + bounty) * (mult - 1);
    }

    /// @dev The day ticket's bet id for `who` — the seat number `_daySeated` now stores.
    function _dayBetId(uint24 day, address who) internal view returns (uint256) {
        uint256 seat = craps.daySeatNumberOf(day, who);
        require(seat != 0, "no day seat");
        return ((uint256(day) * craps.BONUS_SLOTS_PER_DAY()) << 64) | seat;
    }

    /// @dev Arm `period`'s window, land `word` on its table, and settle the whole field.
    function _armAndSettle(uint24 day, uint256 period, uint256 word)
        internal
        returns (Vm.Log[] memory logs)
    {
        uint64 slot = _slotAt(day, period);
        uint48 index = craps.armBonusWindow(slot);
        _setWord(index, word);
        vm.recordLogs();
        craps.resolveSlot(slot, WHOLE_FIELD);
        logs = vm.getRecordedLogs();
    }

    /// @dev The `paid` a `CrapsBetSettled` log reported for one bet.
    function _settledPaid(Vm.Log[] memory logs, uint256 betId) internal pure returns (uint256) {
        bytes32 sig = keccak256("CrapsBetSettled(uint256,address,uint256,uint256)");
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length == 3 && logs[i].topics[0] == sig && uint256(logs[i].topics[1]) == betId) {
                (, uint256 paid) = abi.decode(logs[i].data, (uint256, uint256));
                return paid;
            }
        }
        revert("bet never settled");
    }

    // ── Pricing and the packed state ────────────────────────────────────────

    /// @dev ONE selected period charges exactly `(bankroll + bounty) * (H - 1)` — the ticket
    ///      already supplies the missing 1x — and marks exactly that period's flag and counter.
    function test_anUpgradeChargesExactlyTheMissingCopies() public {
        uint24 day = _openDay(10);
        _buyNormalDay(alice);
        uint256 want = _deltaOf(day, 3, 10);

        uint256 before = flip.burned(alice);
        vm.prank(alice);
        uint256 burned = craps.upgradeDayWindows(day, uint8(1 << 3));

        assertEq(burned, want, "the delta is not the missing H - 1 copies");
        assertEq(flip.burned(alice) - before, burned, "the burn does not match the report");
        assertEq(craps.daySeatHighMaskOf(day, alice), 1 << 3, "the wrong period was flagged");
        assertEq(craps.dayHighTicketsOf(day, 3), 1, "the period's high count did not move");
        for (uint256 p = 0; p < 7; ++p) {
            if (p == 3) continue;
            assertEq(craps.dayHighTicketsOf(day, p), 0, "an unselected period joined the lane");
        }
    }

    /// @dev A HUNDRED-times day prices AND settles the same way: 99 missing copies bought, one
    ///      hundred copies of the one run paid.
    function test_aHundredTimesDayChargesAndPaysNinetyNineMoreCopies() public {
        uint24 day = _openDay(100);
        _buyNormalDay(alice);
        uint256 want = _deltaOf(day, 2, 100);

        vm.prank(alice);
        uint256 burned = craps.upgradeDayWindows(day, uint8(1 << 2));
        assertEq(burned, want, "the tail day did not price at 99 missing copies");
        assertEq(craps.dayHighTicketsOf(day, 2), 1, "the tail day's counter did not move");

        uint256 betId = _dayBetId(day, alice);
        vm.warp(vm.getBlockTimestamp() + 9 hours);
        Vm.Log[] memory logs = _armAndSettle(day, 2, uint256(keccak256("tail")));
        (bytes32 key,,,) = craps.bonusWindowOf(2);
        (uint32 heads,,,,) = craps.highFieldOf(key);
        assertEq(heads, 1, "the upgraded seat did not ride the tail day's lane");
        (, uint256 basePaid) = craps.dayRunAt(betId, _slotAt(day, 2));
        assertGe(_settledPaid(logs, betId), basePaid * 100, "the tail day did not pay all hundred copies");
    }

    /// @dev A multi-period mask charges the exact sum of each selected window's own delta, and
    ///      one call announces exactly the new bits and the exact total.
    function test_aMultiPeriodMaskChargesTheExactSum() public {
        uint24 day = _openDay(10);
        _buyNormalDay(alice);
        uint256 want = _deltaOf(day, 1, 10) + _deltaOf(day, 4, 10) + _deltaOf(day, 6, 10);

        vm.expectEmit(address(craps));
        emit CrapsDayWindowsUpgraded(alice, day, uint8((1 << 1) | (1 << 4) | (1 << 6)), want);
        vm.prank(alice);
        uint256 burned = craps.upgradeDayWindows(day, uint8((1 << 1) | (1 << 4) | (1 << 6)));
        assertEq(burned, want, "three windows did not charge their three deltas");
        assertEq(craps.daySeatHighMaskOf(day, alice), (1 << 1) | (1 << 4) | (1 << 6));
    }

    /// @dev Repeating an upgrade can neither burn nor count twice: an all-old mask reverts, and
    ///      a mixed mask charges only its fresh bits.
    function test_aRepeatCannotChargeOrCountTwice() public {
        uint24 day = _openDay(10);
        _buyNormalDay(alice);
        vm.prank(alice);
        craps.upgradeDayWindows(day, uint8(1 << 2));

        vm.prank(alice);
        vm.expectRevert(CrapsBattle.NothingToUpgrade.selector);
        craps.upgradeDayWindows(day, uint8(1 << 2));

        // Mixed: the old bit rides along free, only the new one is charged and counted.
        uint256 want = _deltaOf(day, 5, 10);
        vm.prank(alice);
        uint256 burned = craps.upgradeDayWindows(day, uint8((1 << 2) | (1 << 5)));
        assertEq(burned, want, "an already-high bit was charged again");
        assertEq(craps.dayHighTicketsOf(day, 2), 1, "an already-high bit was counted again");
        assertEq(craps.dayHighTicketsOf(day, 5), 1, "the fresh bit was not counted");
    }

    /// @dev A zero mask, and a mask with bits past the seventh period, buy nothing anywhere.
    function test_anEmptyOrOverwideMaskReverts() public {
        uint24 day = _openDay(10);
        _buyNormalDay(alice);

        vm.prank(alice);
        vm.expectRevert(CrapsBattle.NothingToUpgrade.selector);
        craps.upgradeDayWindows(day, 0);

        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BonusPeriodSpent.selector);
        craps.upgradeDayWindows(day, 0x80);
    }

    // ── The doors that stay shut ────────────────────────────────────────────

    /// @dev A batch naming ONE unavailable window reverts whole: nothing burns, nothing counts.
    ///      Period 1 here is closed by the CLOCK and nobody has armed it — the lock is the entry
    ///      close itself, not the arm that follows it.
    function test_aMaskNamingAClockClosedWindowRevertsAtomically() public {
        uint24 day = _openDay(10);
        _buyNormalDay(alice);
        // Past period 1's close (03:00, elapsed 4h03m) but before period 2's.
        vm.warp(vm.getBlockTimestamp() + 5 hours);
        assertEq(craps.slotIndexOf(_slotAt(day, 1)), 0, "the fixture armed what it meant to leave");

        uint256 before = flip.burned(alice);
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BonusPeriodSpent.selector);
        craps.upgradeDayWindows(day, uint8((1 << 1) | (1 << 3)));

        assertEq(flip.burned(alice), before, "a reverted batch still burned");
        assertEq(craps.dayHighTicketsOf(day, 3), 0, "a reverted batch still counted its good bit");
        assertEq(craps.daySeatHighMaskOf(day, alice), 0, "a reverted batch still flagged the ticket");

        // The still-open windows alone are fine.
        vm.prank(alice);
        craps.upgradeDayWindows(day, uint8(1 << 3));
        assertEq(craps.daySeatHighMaskOf(day, alice), 1 << 3);
    }

    /// @dev An ARMED window is locked the same way, whatever the clock still says elsewhere.
    function test_anArmedWindowCannotBeUpgraded() public {
        uint24 day = _openDay(10);
        _buyNormalDay(alice);
        vm.warp(vm.getBlockTimestamp() + 5 hours);
        craps.armBonusWindow(_slotAt(day, 1));

        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BonusPeriodSpent.selector);
        craps.upgradeDayWindows(day, uint8(1 << 1));
    }

    /// @dev No ticket, no upgrade — and no way to reach anyone else's. The seat lookup is keyed
    ///      to the caller, so bob naming alice's day still finds only his own missing ticket.
    function test_onlyTheTicketsOwnHolderCanUpgradeIt() public {
        uint24 day = _openDay(10);
        _buyNormalDay(alice);

        vm.prank(bob);
        vm.expectRevert(CrapsBattle.NoSuchBet.selector);
        craps.upgradeDayWindows(day, uint8(1 << 3));
        assertEq(craps.daySeatHighMaskOf(day, alice), 0, "a stranger's call moved the ticket");
    }

    /// @dev An unworded FUTURE reservation cannot be priced: the day's terms and multiple do not
    ///      exist yet. Once the day opens, the same ticket upgrades at the day's OWN terms.
    function test_aFutureReservationWaitsForItsDayToOpen() public {
        _warpToDayStart();
        uint24 target = craps.currentDayIndex() + 1;
        vm.prank(alice);
        craps.buyFutureCrapsDays(target, 1, false);

        vm.prank(alice);
        vm.expectRevert(LootboxCraps.RngNotReady.selector);
        craps.upgradeDayWindows(target, uint8(1 << 3));

        vm.warp(vm.getBlockTimestamp() + 1 days);
        _setDailyWord(target, _wordFor(10));
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();

        uint256 want = _deltaOf(target, 3, 10);
        vm.prank(alice);
        assertEq(craps.upgradeDayWindows(target, uint8(1 << 3)), want, "the open day did not price the upgrade");
    }

    /// @dev A banked pass is not a ticket: credits alone hold no seat to upgrade.
    function test_aBankedPassCannotBeUpgraded() public {
        uint24 day = _openDay(10);
        vm.prank(ContractAddresses.GAME);
        craps.creditPasses(alice, 3, 0);

        vm.prank(alice);
        vm.expectRevert(CrapsBattle.NoSuchBet.selector);
        craps.upgradeDayWindows(day, uint8(1 << 1));
    }

    /// @dev Upgrading is not a quest: the streak was credited when the day was taken, once.
    function test_anUpgradeAwardsNoQuestStreak() public {
        uint24 day = _openDay(10);
        _buyNormalDay(alice);
        uint256 calls = quests.streakCalls(alice);
        uint256 amount = quests.streakAwarded(alice);

        vm.prank(alice);
        craps.upgradeDayWindows(day, uint8((1 << 1) | (1 << 2)));
        assertEq(quests.streakCalls(alice), calls, "an upgrade rang the quest ledger");
        assertEq(quests.streakAwarded(alice), amount, "an upgrade moved the streak");
    }

    // ── Whole-day high tickets under the per-period packing ─────────────────

    /// @dev A native whole-day high entry is high in ALL SEVEN periods: every flag, every
    ///      counter — and it has nothing left to upgrade.
    function test_aWholeDayHighTicketIsHighInAllSevenPeriods() public {
        uint24 day = _openDay(10);
        Craps.Bets memory blank;
        vm.prank(alice);
        craps.enterBonusDay(blank, 10);

        assertEq(craps.daySeatHighMaskOf(day, alice), 0x7F, "a whole-day high is missing period flags");
        for (uint256 p = 0; p < 7; ++p) {
            assertEq(craps.dayHighTicketsOf(day, p), 1, "a period's counter missed the whole-day high");
        }
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.NothingToUpgrade.selector);
        craps.upgradeDayWindows(day, 0x7F);
    }

    /// @dev A HIGH future reservation carries the whole-day shape too, priced only when its day
    ///      draws: all seven flags, all seven counters, at whatever multiple the day lands on.
    function test_aHighFutureReservationSetsAllSevenPeriods() public {
        _warpToDayStart();
        uint24 target = craps.currentDayIndex() + 1;
        vm.prank(alice);
        craps.buyFutureCrapsDays(target, 1, true);

        assertEq(craps.daySeatHighMaskOf(target, alice), 0x7F, "the reservation is not whole-day high");
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _setDailyWord(target, _wordFor(100));
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        for (uint256 p = 0; p < 7; ++p) {
            assertEq(craps.dayHighTicketsOf(target, p), 1, "a period's counter missed the reservation");
        }
        assertEq(craps.highMultForDay(target), 100, "the fixture did not land the tail");
    }

    // ── Settlement: the upgraded window IS a native high seat ───────────────

    /// @dev THE EQUIVALENCE, measured rather than argued: the same day, the same words and the
    ///      same seat number, run once as a normal ticket upgraded at one window and once as a
    ///      native whole-day high — the upgraded window's settlement, its lane payment and both
    ///      action books match to the wei.
    function test_anUpgradedWindowSettlesExactlyAsANativeHighSeat() public {
        uint24 day = _openDay(10);
        uint256 word = uint256(keccak256("equivalence"));
        uint256 dayStart = vm.getBlockTimestamp();
        uint256 snap = vm.snapshotState();

        // ARM A: a normal ticket bought in period zero, upgraded at period 1 alone.
        _buyNormalDay(alice);
        vm.prank(alice);
        craps.upgradeDayWindows(day, uint8(1 << 1));
        vm.warp(dayStart + 5 hours);
        _armAndSettle(day, 1, word);
        uint256 paidA = coinflip.staked(alice);
        uint256 stakedA = craps.dayStaked(day);
        uint256 highA = craps.highStakedOf(day);

        // ARM B: a native whole-day high seat — same address, same seat number, same table. The
        // explicit re-warp keeps the flow honest whether or not the snapshot restores the clock.
        vm.revertToState(snap);
        vm.warp(dayStart);
        Craps.Bets memory blank;
        vm.prank(alice);
        craps.enterBonusDay(blank, 10);
        vm.warp(dayStart + 5 hours);
        _armAndSettle(day, 1, word);

        assertEq(coinflip.staked(alice), paidA, "the upgraded seat and the native one paid apart");
        assertEq(craps.dayStaked(day), stakedA, "the two seats booked different total action");
        assertEq(craps.highStakedOf(day), highA, "the two seats booked different high action");
        assertGt(highA, 0, "the fixture never booked high action at all");
    }

    /// @dev The unselected window of an upgraded ticket stays an ordinary 1x seat outside the
    ///      lane: no high head, and paid exactly the unscaled run.
    function test_theOtherWindowsStayOrdinary() public {
        uint24 day = _openDay(10);
        _buyNormalDay(alice);
        vm.prank(alice);
        craps.upgradeDayWindows(day, uint8(1 << 1));
        uint256 betId = _dayBetId(day, alice);

        vm.warp(vm.getBlockTimestamp() + 9 hours);
        Vm.Log[] memory logs = _armAndSettle(day, 2, uint256(keccak256("plain")));

        (bytes32 key,,,) = craps.bonusWindowOf(2);
        (uint32 heads,,,,) = craps.highFieldOf(key);
        assertEq(heads, 0, "an unselected window grew a lane");
        (, uint256 basePaid) = craps.dayRunAt(betId, _slotAt(day, 2));
        assertEq(_settledPaid(logs, betId), basePaid, "the unselected window did not pay plain 1x");
    }

    /// @dev The upgraded window pays H times the unscaled run, and the upgrade adds NO main
    ///      entrant: the field is still the three day seats it always was.
    function test_theUpgradedWindowPaysTheMultipleAndAddsNoMainHead() public {
        uint24 day = _openDay(10);
        _buyNormalDay(alice);
        vm.prank(alice);
        craps.upgradeDayWindows(day, uint8(1 << 1));
        uint256 betId = _dayBetId(day, alice);

        vm.warp(vm.getBlockTimestamp() + 5 hours);
        Vm.Log[] memory logs = _armAndSettle(day, 1, uint256(keccak256("scaled")));

        (bytes32 key,,,) = craps.bonusWindowOf(1);
        assertEq(craps.battleOf(key).entrants, 3, "the upgrade changed the main head count");
        (uint32 heads,,,,) = craps.highFieldOf(key);
        assertEq(heads, 1, "the upgraded seat did not join its window's lane once");
        (, uint256 basePaid) = craps.dayRunAt(betId, _slotAt(day, 1));
        // The settled figure carries the sole rider's extra-bounty return on top of H copies.
        assertGe(_settledPaid(logs, betId), basePaid * 10, "the upgraded window did not pay all ten copies");
    }

    /// @dev A lane of ONE — the upgraded seat alone — settles as the sole rider: its extra
    ///      bounties ride its own run, and the lane closes with it.
    function test_anUpgradedSeatAloneRidesItsExtraBounties() public {
        uint24 day = _openDay(10);
        _buyNormalDay(alice);
        vm.prank(alice);
        craps.upgradeDayWindows(day, uint8(1 << 1));
        uint256 betId = _dayBetId(day, alice);

        vm.warp(vm.getBlockTimestamp() + 5 hours);
        Vm.Log[] memory logs = _armAndSettle(day, 1, uint256(keccak256("rider")));

        PaidOut[] memory rides = _lanePaymentsIn(logs, true);
        assertEq(rides.length, 1, "the sole rider did not settle its lane on its own run");
        assertEq(rides[0].betId, betId, "the rider payment named the wrong seat");
        (bytes32 key,,,) = craps.bonusWindowOf(1);
        (,,,, bool done) = craps.highFieldOf(key);
        assertTrue(done, "the sole lane did not close with its seat");

        // The ride is the run's return on the H - 1 extra bounties, pro rata — exactly what the
        // shared settlement math says it is.
        (uint128 bank,,, uint256 bounty,,) = craps.bonusTermsFor(day, 1);
        (, uint256 basePaid) = craps.dayRunAt(betId, _slotAt(day, 1));
        uint256 extra = 9 * bounty;
        uint256 want = (basePaid / uint256(bank)) * extra + ((basePaid % uint256(bank)) * extra) / uint256(bank);
        assertEq(rides[0].amount, want, "the ride is not the pro-rata return on the extra bounties");
    }

    /// @dev CONTESTED: an upgraded ticket races a direct high entry for every extra bounty in
    ///      the lane — two heads, one lane pot of `heads * (H - 1)` bounties.
    function test_anUpgradedSeatContestsTheLaneWithADirectHighEntry() public {
        uint24 day = _openDay(10);
        _buyNormalDay(alice);
        vm.prank(alice);
        craps.upgradeDayWindows(day, uint8(1 << 1));
        Craps.Bets memory blank;
        vm.prank(dave);
        craps.enterBonusBattle(1, blank, 10);

        vm.warp(vm.getBlockTimestamp() + 5 hours);
        Vm.Log[] memory logs = _armAndSettle(day, 1, uint256(keccak256("contest")));

        (bytes32 key,,,) = craps.bonusWindowOf(1);
        (uint32 heads,,,,) = craps.highFieldOf(key);
        assertEq(heads, 2, "the lane did not hold both high seats");

        PaidOut[] memory pays = _lanePaymentsIn(logs, false);
        assertEq(pays.length, 1, "a contested lane pays exactly once");
        (,,, uint256 bounty,,) = craps.bonusTermsFor(day, 1);
        assertEq(pays[0].amount, 2 * 9 * bounty, "the lane pot is not both seats' extra bounties");
        assertTrue(
            pays[0].player == alice || pays[0].player == dave,
            "the lane paid outside its own two seats"
        );
    }
}
