// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {CrapsPins, MockFlip} from "./CrapsPins.sol";

contract CompHarness is CrapsViews {
    function highSeatsOf(bytes32 key) external view returns (uint256) {
        return uint32(_highField[key]);
    }

    function windowOf(uint64 slot) external view returns (uint256 bankroll, uint256 highMult, uint256 stakeUnits) {
        Window memory w = _slotWindow(slot);
        return (w.bankroll, w.highMult, w.stakeUnits);
    }

    function fieldOf(bytes32 key) external view returns (uint256 entrants, uint256 resolved) {
        uint256 g = _battles[key];
        return (g & _MASK32, (g >> _BG_RESOLVED_SHIFT) & _MASK32);
    }
}

/// @dev The comp lane's two halves: what a finished field FEEDS it (two percent of the bankroll
///      every seat ran, once, whichever way the field settled) and what the vault's comp door
///      SPENDS from it (exactly what the paid door burns, for a seat the paid path would have
///      written identically).
contract CrapsCompBudgetTest is CrapsPins {
    CompHarness internal craps;

    uint256 internal constant PLAIN_WORD = 40 << 8;
    uint256 internal constant GRANULE = 100e18;

    uint8 internal constant KIND_WINDOW = 0;
    uint8 internal constant KIND_DAY = 1;
    uint8 internal constant KIND_FUTURE_DAYS = 2;
    uint8 internal constant KIND_UPGRADE = 3;
    uint8 internal constant KIND_PASSES = 4;
    uint8 internal constant KIND_WINDOW_AHEAD = 5;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");
    address internal erin = makeAddr("erin");

    function setUp() public {
        _installPins();
        craps = new CompHarness();
        vm.warp(block.timestamp + 1 days);
        _setIndex(4);
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
        uint256 floor_ = craps.SYBIL_SCORE_FLOOR();
        game.setScore(alice, floor_);
        game.setScore(bob, floor_);
        game.setScore(carol, floor_);
        game.setScore(dave, floor_);
        game.setScore(erin, floor_);
        // The pins open the lane on a wei; a comp needs something to spend.
        flip.setCompLane(100_000_000 ether);
    }

    // ── fixtures ────────────────────────────────────────────────────────────

    function _blank() internal pure returns (Craps.Bets memory b) {}

    function _warpToDayStart() internal {
        uint256 elapsed = (vm.getBlockTimestamp() - 82_620) % 1 days;
        if (elapsed != 0) vm.warp(vm.getBlockTimestamp() + (1 days - elapsed));
    }

    function _wordFor(uint256 want) internal view returns (uint256) {
        for (uint256 i = 1; i < 500; ++i) {
            uint256 w = uint256(keccak256(abi.encode("comp", i)));
            if (craps.highMultOfWord(w) == want) return w;
        }
        revert("no word draws that multiple");
    }

    function _openDay(uint256 mult) internal returns (uint24 day) {
        _warpToDayStart();
        day = craps.currentDayIndex();
        _setDailyWord(day, _wordFor(mult));
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
    }

    function _slotAt(uint24 day, uint256 period) internal view returns (uint64) {
        return uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + period + 1);
    }

    function _priceOf(uint24 day, uint256 period, uint256 mult) internal view returns (uint256) {
        (uint128 bank,,, uint256 bounty,,) = craps.bonusTermsFor(day, period);
        return (uint256(bank) + bounty) * mult;
    }

    function _seat(address who, uint256 period, uint16 mult) internal returns (uint256 betId) {
        vm.prank(who);
        betId = craps.enterBonusBattle(period, _blank(), mult);
    }

    function _code(uint8 kind, address to, bool high, uint24 arg, uint8 count) internal pure returns (uint256) {
        return uint256(uint160(to)) | (uint256(kind) << 160) | (high ? (1 << 168) : 0) | (uint256(arg) << 176)
            | (uint256(count) << 200);
    }

    function _ahead(address to, bool high, uint24 day, uint8 period, uint8 count) internal returns (uint256 charged) {
        vm.prank(ContractAddresses.VAULT);
        charged = craps.vaultComp(_code(KIND_WINDOW_AHEAD, to, high, day, count) | (uint256(period) << 208));
    }

    function _comp(uint8 kind, address to, bool high, uint24 arg, uint8 count) internal returns (uint256 charged) {
        vm.prank(ContractAddresses.VAULT);
        charged = craps.vaultComp(_code(kind, to, high, arg, count));
    }

    function _pastWindow(uint256 period) internal {
        uint256 ts = vm.getBlockTimestamp();
        uint256 dayStart = ts - ((ts - 82_620) % 1 days);
        uint256 shut = dayStart + 1 hours + period * 4 hours;
        if (ts < shut) vm.warp(shut);
    }

    function _arm(uint24 day, uint256 period, uint256 word) internal returns (uint64 slot) {
        slot = _slotAt(day, period);
        _pastWindow(period);
        uint48 index = craps.armBonusWindow(slot);
        _setWord(index, word);
    }

    function _settle(uint24 day, uint256 period, uint256 word, uint64 budget) internal returns (uint256 entrants) {
        uint64 slot = _arm(day, period, word);
        entrants = _entrantsIn(slot);
        craps.resolveSlot(slot, budget);
    }

    /// @dev The field as it is frozen at the arm — players, folded day tickets and the protocol
    ///      bodies the arm seats — which is what the oracle counts seats over.
    function _entrantsIn(uint64 slot) internal view returns (uint256 entrants) {
        (entrants,) = craps.fieldOf(craps.battleKeyOf((uint256(slot) << 64) | 1));
    }

    function _expected(uint256 bankroll, uint256 seats, uint256 highSeats, uint256 highMult)
        internal
        pure
        returns (uint256)
    {
        uint256 eligible = bankroll * seats;
        if (highSeats != 0) eligible += bankroll * highSeats * (highMult - 1);
        return eligible / 50;
    }

    // ── Accrual ─────────────────────────────────────────────────────────────

    function test_aFinishedWindowFeedsTwoPercentOfEveryBankrollItRan() public {
        uint24 day = _openDay(10);
        _seat(alice, 1, 1);
        _seat(bob, 1, 1);
        _seat(carol, 1, 10);
        (uint256 bank,,) = craps.windowOf(_slotAt(day, 1));
        uint256 before = flip.compLane();
        uint256 n = _settle(day, 1, 0xBEEF, WHOLE_FIELD);
        assertGe(n, 3, "the field lost a player");
        assertEq(flip.compLane() - before, _expected(bank, n, 1, 10), "the lane did not earn 2% of the bankroll run");
        assertEq(flip.compAccruals(), 1, "the field fed the lane other than exactly once");
    }

    function test_aDayTicketCountsInEveryWindowItSitsIn() public {
        uint24 day = _openDay(10);
        vm.prank(alice);
        craps.enterBonusDay(_blank(), 1);
        _seat(bob, 1, 1);
        (uint256 bank,,) = craps.windowOf(_slotAt(day, 1));
        uint256 before = flip.compLane();
        uint256 n = _settle(day, 1, 0xBEEF, WHOLE_FIELD);
        assertGe(n, 2, "the day seat did not fold into the field");
        assertEq(flip.compLane() - before, _expected(bank, n, 0, 10), "the folded day seat did not earn its bankroll");
    }

    function test_anUpgradedDayWindowEarnsAsAHighSeatThereOnly() public {
        uint24 day = _openDay(10);
        vm.prank(alice);
        craps.enterBonusDay(_blank(), 1);
        vm.prank(alice);
        craps.upgradeDayWindows(day, 1 << 1);
        _seat(bob, 1, 1);
        _seat(carol, 2, 1);
        (uint256 bank1,,) = craps.windowOf(_slotAt(day, 1));
        (uint256 bank2,,) = craps.windowOf(_slotAt(day, 2));
        uint256 before = flip.compLane();
        uint256 n = _settle(day, 1, 0xBEEF, WHOLE_FIELD);
        assertEq(flip.compLane() - before, _expected(bank1, n, 1, 10), "the upgraded window did not earn the high copies");
        before = flip.compLane();
        n = _settle(day, 2, 0xBEEF, WHOLE_FIELD);
        assertEq(flip.compLane() - before, _expected(bank2, n, 0, 10), "an un-upgraded window earned high copies");
    }

    function test_aCustomBattleWithNoBountyAndNoHighLaneStillEarns() public {
        uint64 slot = _openBattle(craps, 300, 4, 5, 0);
        vm.prank(alice);
        craps.enterBattle(slot, _blank(), 1);
        vm.prank(bob);
        craps.enterBattle(slot, _blank(), 1);
        (uint256 bank, uint256 highMult,) = craps.windowOf(slot);
        assertEq(highMult, 0, "the fixture opened a high lane");
        uint256 before = flip.compLane();
        _closeOn(craps, slot, 9, 0xBEEF);
        craps.resolveSlot(slot, WHOLE_FIELD);
        assertEq(flip.compLane() - before, _expected(bank, 2, 0, 0), "a custom field earned other than 2% of its bankrolls");
    }

    function test_theCreditIsTheSameHoweverTheSettlementIsChunked() public {
        uint24 dayA = _openDay(10);
        address[6] memory who = [alice, bob, carol, dave, erin, makeAddr("fay")];
        game.setScore(who[5], craps.SYBIL_SCORE_FLOOR());
        for (uint256 i = 0; i < 6; ++i) {
            _seat(who[i], 1, i == 2 ? 10 : 1);
        }
        (uint256 bank,,) = craps.windowOf(_slotAt(dayA, 1));
        uint256 before = flip.compLane();
        uint64 slot = _arm(dayA, 1, 0xBEEF);
        uint256 want = _expected(bank, _entrantsIn(slot), 1, 10);
        // One seat at a time: a budget of one unit walks exactly one seat per call.
        bytes32 key = craps.battleKeyOf((uint256(slot) << 64) | 1);
        for (uint256 guard = 0; guard < 32; ++guard) {
            (uint256 entrants, uint256 resolved) = craps.fieldOf(key);
            if (resolved == entrants) break;
            assertEq(flip.compLane(), before, "the lane was fed before the field finished");
            craps.resolveSlot(slot, 1);
        }
        assertEq(flip.compLane() - before, want, "chunked settlement fed a different figure");
        assertEq(flip.compAccruals(), 1, "chunked settlement fed the lane more than once");

        // A retry on the finished slot feeds nothing.
        craps.resolveSlot(slot, WHOLE_FIELD);
        assertEq(flip.compAccruals(), 1, "a settled slot fed the lane again");
    }

    function test_theOutcomeDoesNotChangeTheCredit() public {
        uint24 day = _openDay(10);
        _seat(alice, 1, 1);
        _seat(bob, 1, 10);
        _seat(carol, 2, 1);
        _seat(dave, 2, 10);
        uint256 before = flip.compLane();
        _settle(day, 1, 0xBEEF, WHOLE_FIELD);
        uint256 earned1 = flip.compLane() - before;
        before = flip.compLane();
        _settle(day, 2, uint256(keccak256("a different table")), WHOLE_FIELD);
        uint256 earned2 = flip.compLane() - before;
        (uint256 bank1,,) = craps.windowOf(_slotAt(day, 1));
        (uint256 bank2,,) = craps.windowOf(_slotAt(day, 2));
        assertEq(earned1 * bank2, earned2 * bank1, "two same-shaped fields earned differently under different dice");
    }

    function test_donationsDoNotEarn() public {
        uint24 day = _openDay(10);
        _seat(alice, 1, 1);
        _seat(bob, 1, 1);
        vm.prank(carol);
        craps.donate(false, 1, 50);
        (uint256 bank,,) = craps.windowOf(_slotAt(day, 1));
        uint256 before = flip.compLane();
        uint256 n = _settle(day, 1, 0xBEEF, WHOLE_FIELD);
        assertEq(flip.compLane() - before, _expected(bank, n, 0, 10), "a donation entered the accrual");
    }

    // ── The comp door ───────────────────────────────────────────────────────

    function test_aCompedWindowSeatIsThePaidSeatWithAnotherOwner() public {
        uint24 day = _openDay(10);
        uint256 paidId = _seat(alice, 1, 1);
        uint256 price = _priceOf(day, 1, 1);
        uint256 charged = _comp(KIND_WINDOW, dave, false, 1, 0);
        assertEq(charged, price, "the door quoted a price other than the paid seat's");
        assertEq(flip.compFor(dave), price, "the lane was charged other than the seat's price");
        assertEq(flip.burned(dave), 0, "the recipient's own FLIP was burned");
        uint256 compId = (uint256(_slotAt(day, 1)) << 64) | 2;
        uint256 paid = craps.betWordOf(paidId);
        uint256 comp = craps.betWordOf(compId);
        assertEq(address(uint160(comp)), dave, "the comped seat belongs to somebody else");
        assertEq(comp >> 160, paid >> 160, "the comped seat differs from the paid one above the owner");
    }

    function test_aCompedHighSeatCountsInTheHighLane() public {
        uint24 day = _openDay(10);
        uint256 charged = _comp(KIND_WINDOW, dave, true, 1, 0);
        assertEq(charged, _priceOf(day, 1, 10), "a high comp was priced other than ten seats");
        bytes32 key = craps.battleKeyOf((uint256(_slotAt(day, 1)) << 64) | 1);
        assertEq(craps.highSeatsOf(key), 1, "the comped high seat is not in the lane");
    }

    function test_aCompCannotSeatTheSameAddressTwice() public {
        uint24 day = _openDay(10);
        _seat(dave, 1, 1);
        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert(CrapsBattle.AlreadyInBonus.selector);
        craps.vaultComp(_code(KIND_WINDOW, dave, false, 1, 0));
        day;
    }

    function test_aCompedDayIsThePaidDay() public {
        uint24 day = _openDay(10);
        vm.prank(bob);
        craps.enterBonusDay(_blank(), 1);
        uint256 paid = flip.burned(bob);
        uint256 charged = _comp(KIND_DAY, dave, false, 0, 0);
        assertEq(charged, paid, "the comped day was priced other than the paid one");
        assertEq(flip.compFor(dave), paid, "the lane was charged other than the day's price");
        assertTrue(craps.daySeatNumberOf(day, dave) != 0, "the recipient holds no day seat");
        assertEq(
            craps.betWordOf(((uint256(day) * craps.BONUS_SLOTS_PER_DAY()) << 64) | craps.daySeatNumberOf(day, dave)) >> 160,
            craps.betWordOf(((uint256(day) * craps.BONUS_SLOTS_PER_DAY()) << 64) | craps.daySeatNumberOf(day, bob)) >> 160,
            "the comped day seat differs from the paid one above the owner"
        );
    }

    function test_compedFutureDaysAreThePaidReservation() public {
        uint24 day = _openDay(10);
        vm.prank(bob);
        craps.buyFutureCrapsDays(day + 1, 2, false);
        uint256 charged = _comp(KIND_FUTURE_DAYS, dave, false, day + 1, 2);
        assertEq(charged, flip.burned(bob), "two comped days were priced other than two bought days");
        assertEq(flip.compFor(dave), charged, "the lane was charged other than the price");
        assertTrue(craps.dayStateOf(day + 1, dave) != 0 && craps.dayStateOf(day + 2, dave) != 0, "a day is not reserved");
        // High lane: anything above one.
        uint256 hi = _comp(KIND_FUTURE_DAYS, erin, true, day + 3, 1);
        assertEq(hi, craps.HIGH_FUTURE_DAY_PRICE(), "a high reservation was priced other than the fixed high price");
    }

    function test_aCompedUpgradeChargesTheMissingCopies() public {
        uint24 day = _openDay(10);
        _comp(KIND_DAY, dave, false, 0, 0);
        vm.prank(bob);
        craps.enterBonusDay(_blank(), 1);
        vm.prank(bob);
        uint256 paid = craps.upgradeDayWindows(day, (1 << 2) | (1 << 5));
        uint256 laneBefore = flip.compFor(dave);
        uint256 charged = _comp(KIND_UPGRADE, dave, false, day, (1 << 2) | (1 << 5));
        assertEq(charged, paid, "the comped upgrade was priced other than the paid one");
        assertEq(flip.compFor(dave) - laneBefore, paid, "the lane was charged other than the delta");
        assertEq(craps.daySeatHighMaskOf(day, dave), (1 << 2) | (1 << 5), "the upgrade bits were not written");
        // Already-high bits are not charged again; a mask of only those buys nothing.
        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert(CrapsBattle.NothingToUpgrade.selector);
        craps.vaultComp(_code(KIND_UPGRADE, dave, false, day, 1 << 2));
    }

    function test_compedPassesBankAndChargeOnlyWhatBanked() public {
        uint256 charged = _comp(KIND_PASSES, dave, false, 0, 3);
        assertEq(charged, 3 * craps.NORMAL_PASS_VALUE(), "three normals were priced other than three pass values");
        (uint256 n, uint256 h) = craps.passCreditsOf(dave);
        assertEq(n, 3, "the normals did not bank");
        charged = _comp(KIND_PASSES, dave, true, 0, 1);
        assertEq(charged, craps.HIGH_PASS_VALUE(), "a high pass was priced other than its value");
        (, h) = craps.passCreditsOf(dave);
        assertEq(h, 1, "the high pass did not bank");
        // A nearly full lane banks what fits and bills only that.
        craps.setPassCredits(erin, type(uint32).max - 1, 0);
        charged = _comp(KIND_PASSES, erin, false, 0, 5);
        assertEq(charged, craps.NORMAL_PASS_VALUE(), "a saturated lane was billed for passes it dropped");
        craps.setPassCredits(erin, type(uint32).max, 0);
        assertEq(_comp(KIND_PASSES, erin, false, 0, 1), 0, "a full lane was billed");
    }

    // ── A window on a day ahead ─────────────────────────────────────────────

    function test_aWindowAheadIsPricedAtItsClassesExpectedSeat() public {
        uint24 day = craps.currentDayIndex() + 1;
        assertEq(_ahead(dave, false, day, 0, 1), 2_433 ether, "the opener is not priced at its expected seat");
        assertEq(_ahead(dave, false, day, 3, 2), 2 * 1_227 ether, "a routine window is not priced at its expected seat");
        assertEq(_ahead(dave, false, day, 6, 1), 14_235 ether, "the tail is not priced at its expected seat");
        assertEq(_ahead(erin, true, day, 6, 1), 19 * 14_235 ether, "a high seat is not nineteen expected seats");
        assertEq(flip.compFor(dave), (2_433 + 2 * 1_227 + 14_235) * 1 ether, "the lane was charged other than the sum");
        assertTrue(craps.seatedIn(_slotAt(day, 0), dave) && craps.seatedIn(_slotAt(day, 3), dave) && craps.seatedIn(_slotAt(day, 6), dave), "a window is not held");
        assertTrue(!craps.seatedIn(_slotAt(day, 1), dave), "an unreserved window is held");
        assertTrue(craps.seatedIn(_slotAt(day + 1, 3), dave), "the second day of the run is not reserved");
        (uint256 n, uint256 h) = craps.windowReservedOf(_slotAt(day, 6));
        assertEq(n, 2, "the tail has other than two reserved seats");
        assertEq(h, 1, "the tail has other than one high reservation");
        assertEq(address(uint160(craps.betWordOf((uint256(_slotAt(day, 6)) << 64) | 1))), dave, "seat one is not dave's");
        assertEq(address(uint160(craps.betWordOf((uint256(_slotAt(day, 6)) << 64) | 2))), erin, "seat two is not erin's");
        assertEq(craps.daySeatNumberOf(day, dave), 0, "a window reservation reads as a day ticket");
    }

    function test_theExpectedSeatMatchesThePresetTable() public {
        uint256[3] memory sum;
        uint256 n = 1500;
        uint24 day = craps.currentDayIndex() + 10;
        for (uint256 i = 0; i < n; ++i) {
            _setDailyWord(day, uint256(keccak256(abi.encode("ev", i))));
            sum[0] += _priceOf(day, 0, 1);
            sum[1] += _priceOf(day, 3, 1);
            sum[2] += _priceOf(day, 6, 1);
        }
        assertApproxEqRel(sum[0] / n, 2_433 ether, 0.03e18, "the opener's expected seat drifted from the table");
        assertApproxEqRel(sum[1] / n, 1_227 ether, 0.03e18, "the routine expected seat drifted from the table");
        assertApproxEqRel(sum[2] / n, 14_235 ether, 0.06e18, "the tail's expected seat drifted from the table");
    }

    function test_aReservedWindowIsRefusedWhereItCannotSit() public {
        uint24 today = craps.currentDayIndex();
        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert(CrapsBattle.DayNotReservable.selector);
        craps.vaultComp(_code(KIND_WINDOW_AHEAD, dave, false, today, 1) | (2 << 208));
        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert(CrapsBattle.BonusPeriodSpent.selector);
        craps.vaultComp(_code(KIND_WINDOW_AHEAD, dave, false, today + 1, 1) | (7 << 208));
        _ahead(dave, false, today + 1, 2, 1);
        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert(CrapsBattle.AlreadyInBonus.selector);
        craps.vaultComp(_code(KIND_WINDOW_AHEAD, dave, true, today + 1, 1) | (2 << 208));
        // A day ticket on that day is refused, and a reservation where a day ticket sits.
        _comp(KIND_FUTURE_DAYS, erin, false, today + 1, 1);
        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert(CrapsBattle.AlreadyInBonus.selector);
        craps.vaultComp(_code(KIND_WINDOW_AHEAD, erin, false, today + 1, 1) | (4 << 208));
        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert(CrapsBattle.DayNotReservable.selector);
        craps.vaultComp(_code(KIND_FUTURE_DAYS, dave, false, today + 1, 1));
    }

    function test_aReservedSeatPlaysItsWindowAndNumbersTheFieldFromIt() public {
        _warpToDayStart();
        uint24 day = craps.currentDayIndex() + 1;
        _ahead(dave, false, day, 1, 1);
        _ahead(erin, true, day, 1, 1);
        _ahead(carol, false, day, 2, 1);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertEq(_openDay(10), day, "the fixture opened a different day");
        // Live entrants number on from the reserved seats.
        uint256 aliceId = _seat(alice, 1, 1);
        assertEq(uint64(aliceId), 3, "the first live seat did not follow the two reserved ones");
        // The reserved holders may not take a second seat there, but may sit elsewhere.
        vm.prank(dave);
        vm.expectRevert(CrapsBattle.AlreadyInBonus.selector);
        craps.enterBonusBattle(1, _blank(), 1);
        _seat(dave, 3, 1);
        vm.prank(dave);
        vm.expectRevert(CrapsBattle.AlreadyInBonus.selector);
        craps.enterBonusDay(_blank(), 1);
        vm.prank(dave);
        vm.expectRevert(CrapsBattle.NoSuchBet.selector);
        craps.upgradeDayWindows(day, 1 << 1);
        bytes32 key = craps.battleKeyOf(aliceId);
        assertEq(craps.highSeatsOf(key), 1, "the reserved high seat is not in the lane");
        (uint256 bank,,) = craps.windowOf(_slotAt(day, 1));
        uint256 before = flip.compLane();
        uint256 entrants = _settle(day, 1, 0xBEEF, WHOLE_FIELD);
        assertGe(entrants, 3, "the field lost a seat");
        (, uint256 resolved) = craps.fieldOf(key);
        assertEq(resolved, entrants, "the field did not settle whole");
        assertEq(flip.compLane() - before, _expected(bank, entrants, 1, 10), "the reserved seats did not earn");
        (uint256 n2,) = craps.windowReservedOf(_slotAt(day, 2));
        assertEq(n2, 1, "window two lost its reservation");
    }

    function test_aCompCarriesNoBoon() public {
        uint24 day = _openDay(10);
        flip.setNextBoonMask(4);
        _comp(KIND_WINDOW, dave, false, 1, 0);
        assertEq(craps.boonMaskOf((uint256(_slotAt(day, 1)) << 64) | 1), 0, "a comp consumed a boon");
        assertEq(flip.nextBoonMask(), 4, "the comp burn consumed the armed boon");
    }

    function test_aCompedSeatStartsBlankAndCanBeRespread() public {
        uint24 day = _openDay(10);
        _comp(KIND_WINDOW, dave, false, 1, 0);
        uint256 betId = (uint256(_slotAt(day, 1)) << 64) | 1;
        assertEq((craps.betWordOf(betId) >> craps.BET_CHIPS_SHIFT()) & craps.BET_CHIPS_MASK(), 0, "a comp named chips");
        Craps.Bets memory b;
        b.passLine = 3;
        b.place6 = 2;
        vm.prank(dave);
        craps.amendSlip(betId, b);
        assertTrue((craps.betWordOf(betId) >> craps.BET_CHIPS_SHIFT()) & craps.BET_CHIPS_MASK() != 0, "the recipient could not re-spread");
    }

    function test_onlyTheVaultMayComp() public {
        _openDay(10);
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.NotVaultOwner.selector);
        craps.vaultComp(_code(KIND_WINDOW, dave, false, 1, 0));
        // An unknown kind is nothing: no seat, no charge.
        assertEq(_comp(9, dave, false, 1, 0), 0, "an unknown kind charged");
    }

    function test_aLaneThatCannotCoverItRefusesTheWholeSeat() public {
        uint24 day = _openDay(10);
        uint64 slot = _slotAt(day, 1);
        flip.setCompLane(_priceOf(day, 1, 1) - 1);
        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert(MockFlip.MockCompLaneShort.selector);
        craps.vaultComp(_code(KIND_WINDOW, dave, false, 1, 0));
        assertEq(craps.betWordOf((uint256(slot) << 64) | 1), 0, "a refused comp left a seat behind");
        flip.setCompLane(_priceOf(day, 1, 1));
        _comp(KIND_WINDOW, dave, false, 1, 0);
        assertEq(flip.compLane(), 0, "the lane was not spent to the wei");
    }
}
