// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {CrapsPins} from "./CrapsPins.sol";

/// @title Day passes, prepaid future days, and the seat they redeem into
/// @notice A pass is a commitment made BLIND: it is bought or awarded before the target day's word
///         exists, so neither the table it will play nor the multiple it will run at is knowable
///         when it is committed. Every rule here exists to keep it that way — a commitment that
///         could be made, moved or cancelled once the terms were visible would be an option on the
///         protocol's own dice, and the holder would only ever exercise it on the good days.
contract CrapsPassesTest is CrapsPins {
    CrapsViews internal craps;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    /// @dev A word whose high draw is the ordinary ten, so a fixture that is not about the tail
    ///      does not accidentally ride one.
    uint256 internal constant PLAIN_WORD = 40 << 8;

    function setUp() public {
        _installPins();
        craps = new CrapsViews();
        // The deployment day is a Craps warm-up day with no windows; every fixture plays
        // from genesis + 1, the first day the table opens.
        vm.warp(block.timestamp + 1 days);
        _setIndex(4);
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
        uint256 floor_ = craps.SYBIL_SCORE_FLOOR();
        game.setScore(alice, floor_);
        game.setScore(bob, floor_);
    }

    function _today() internal view returns (uint24) {
        return craps.currentDayIndex();
    }

    /// @dev To the top of a protocol day, where period zero — the whole-day lane — is live.
    function _warpToDayStart() internal {
        uint256 elapsed = (vm.getBlockTimestamp() - 82_620) % 1 days;
        if (elapsed != 0) vm.warp(vm.getBlockTimestamp() + (1 days - elapsed));
    }

    function _seven() internal pure returns (Craps.Bets memory c) {
        c.passLine = 4;
        c.place8 = 3;
    }

    // ── Delivery ────────────────────────────────────────────────────────────

    /// @dev THE GAME AND NOBODY ELSE awards passes. They are lootbox output, so a player who could
    ///      mint their own would be minting free entries into the protocol's own windows.
    function test_onlyTheGameMayDeliverPasses() public {
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.OnlyGame.selector);
        craps.deliverPasses(alice, 1, 0);

        vm.prank(ContractAddresses.GAME);
        craps.deliverPasses(alice, 1, 0);
        (uint256 n,) = craps.passCreditsOf(alice);
        assertEq(n, 0, "the delivered pass was banked instead of seated");
        assertEq(craps.dayStateOf(_today() + 1, alice), craps.DAY_SEATED(), "tomorrow was not taken");
    }

    /// @dev One pass goes straight onto tomorrow; everything else banks. That is what makes a box
    ///      feel like it paid out today rather than into an inventory screen.
    function test_deliverySeatsTomorrowAndBanksTheRest() public {
        vm.prank(ContractAddresses.GAME);
        uint24 day = craps.deliverPasses(alice, 4, 0);

        assertEq(day, _today() + 1, "the reservation did not land on tomorrow");
        assertEq(craps.dayStateOf(day, alice), craps.DAY_SEATED(), "tomorrow is not reserved");
        (uint256 n, uint256 h) = craps.passCreditsOf(alice);
        assertEq(n, 3, "the remainder was not banked");
        assertEq(h, 0, "a normal award banked a high credit");
    }

    /// @dev A MIXED batch seats the high pass. Only one can be seated and the high one is worth
    ///      nineteen of the other, so seating the cheaper one would hand the player the worse of
    ///      the two outcomes for no reason.
    function test_aMixedBatchSeatsTheHighPassFirst() public {
        vm.prank(ContractAddresses.GAME);
        uint24 day = craps.deliverPasses(alice, 5, 2);

        assertEq(craps.dayStateOf(day, alice), craps.DAY_SEATED(), "tomorrow did not take the high pass");
        assertTrue(craps.daySeatIsHigh(day, alice), "the seated pass was not the high one");
        (uint256 n, uint256 h) = craps.passCreditsOf(alice);
        assertEq(n, 5, "the normal passes were not all banked");
        assertEq(h, 1, "the remaining high pass was not banked");
    }

    /// @dev An UNAVAILABLE tomorrow costs the player nothing: the whole award banks instead. This
    ///      is the fail-open rule that keeps a busy player's boxes paying out normally.
    function test_anOccupiedTomorrowBanksTheWholeAward() public {
        vm.prank(ContractAddresses.GAME);
        craps.deliverPasses(alice, 1, 0);
        uint24 tomorrow = _today() + 1;
        assertEq(craps.dayStateOf(tomorrow, alice), craps.DAY_SEATED(), "the first pass did not seat");

        vm.prank(ContractAddresses.GAME);
        uint24 day = craps.deliverPasses(alice, 3, 0);
        assertEq(day, 0, "a second delivery double-booked the same day");
        (uint256 n,) = craps.passCreditsOf(alice);
        assertEq(n, 3, "the whole second award should have banked");
    }

    /// @dev A day whose WORD HAS LANDED is not reservable, however future it looks. The word is
    ///      what makes the terms knowable, so a commitment past it would not be blind.
    function test_aWordedTomorrowIsNotReservable() public {
        uint24 tomorrow = _today() + 1;
        _setDailyWord(tomorrow, uint256(keccak256("early")));

        vm.prank(ContractAddresses.GAME);
        uint24 day = craps.deliverPasses(alice, 2, 0);
        assertEq(day, 0, "a worded day was reserved");
        (uint256 n,) = craps.passCreditsOf(alice);
        assertEq(n, 2, "the award did not bank instead");
    }

    /// @dev A full lane SATURATES rather than reverting. Lootbox settlement is a permissionless
    ///      sweep, so a balance that could revert on overflow would let one wedged player stall
    ///      everyone else's boxes.
    function test_aFullLaneSaturatesRatherThanReverting() public {
        uint32 max = type(uint32).max;
        vm.prank(ContractAddresses.GAME);
        craps.deliverPasses(alice, max, 0);
        (uint256 n,) = craps.passCreditsOf(alice);
        assertEq(n, uint256(max) - 1, "the first award did not bank whole");

        // Over the ceiling: the excess is dropped and announced, and the call still returns.
        vm.recordLogs();
        vm.prank(ContractAddresses.GAME);
        craps.deliverPasses(alice, 10, 0);
        (n,) = craps.passCreditsOf(alice);
        assertEq(n, max, "the lane did not saturate at its ceiling");

        bytes32 sig = keccak256("CrapsPassesDropped(address,bool,uint256)");
        uint256 dropped;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == sig) {
                (, dropped) = abi.decode(logs[i].data, (bool, uint256));
            }
        }
        assertEq(dropped, 9, "the discarded excess was not announced");
    }

    // ── Committing credits ──────────────────────────────────────────────────

    /// @dev A run of days, all or nothing, off the player's own balance.
    function test_creditsCommitToAConsecutiveRun() public {
        vm.prank(ContractAddresses.GAME);
        craps.deliverPasses(alice, 6, 0);
        // One already rode onto tomorrow, so five remain and the run starts past it.
        uint24 start = _today() + 2;

        vm.prank(alice);
        craps.applyCrapsPasses(start, 4, false);

        (uint256 n,) = craps.passCreditsOf(alice);
        assertEq(n, 1, "the debit was not exactly the run");
        for (uint24 d = start; d < start + 4; ++d) {
            assertEq(craps.dayStateOf(d, alice), craps.DAY_SEATED(), "a day of the run is unreserved");
        }
        assertEq(craps.dayStateOf(start + 4, alice), 0, "the run ran past its count");
    }

    /// @dev SPENDING MORE THAN YOU HOLD takes the whole call down. The debit is the balance check,
    ///      so there is no path where a partial run is written against a short balance.
    function test_aShortBalanceReservesNothing() public {
        vm.prank(ContractAddresses.GAME);
        craps.deliverPasses(alice, 2, 0);
        uint24 start = _today() + 2;

        vm.prank(alice);
        vm.expectRevert();
        craps.applyCrapsPasses(start, 5, false);

        assertEq(craps.dayStateOf(start, alice), 0, "a failed application still wrote a day");
        (uint256 n,) = craps.passCreditsOf(alice);
        assertEq(n, 1, "a failed application still moved the balance");
    }

    /// @dev ONE OCCUPIED DAY VOIDS THE WHOLE RUN — no skipping, no partial credit spend. A run
    ///      with a hole in it is not what the caller asked for, and quietly delivering one would
    ///      spend passes on a different set of days than the one they named.
    function test_oneTakenDayVoidsTheWholeRun() public {
        vm.prank(ContractAddresses.GAME);
        craps.deliverPasses(alice, 9, 0);
        uint24 start = _today() + 2;

        // Take the middle day out from under the run.
        vm.prank(alice);
        craps.applyCrapsPasses(start + 2, 1, false);
        (uint256 before_,) = craps.passCreditsOf(alice);

        vm.prank(alice);
        vm.expectRevert(CrapsBattle.DayNotReservable.selector);
        craps.applyCrapsPasses(start, 5, false);

        (uint256 n,) = craps.passCreditsOf(alice);
        assertEq(n, before_, "the voided run still spent credits");
        assertEq(craps.dayStateOf(start, alice), 0, "the voided run still wrote its first day");
    }

    /// @dev TODAY IS NOT RESERVABLE, and neither is a day already worded. Both would let the
    ///      holder see the terms before committing.
    function test_aRunMustBeStrictlyFutureAndUnworded() public {
        vm.prank(ContractAddresses.GAME);
        craps.deliverPasses(alice, 8, 0);
        // HOISTED. An inline `_today()` would be the call the expectation lands on, and the
        // application below would run unwatched.
        uint24 today = _today();

        vm.prank(alice);
        vm.expectRevert(CrapsBattle.DayNotReservable.selector);
        craps.applyCrapsPasses(today, 1, false);

        uint24 start = today + 3;
        _setDailyWord(start + 1, uint256(keccak256("leaked")));
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.DayNotReservable.selector);
        craps.applyCrapsPasses(start, 3, false);

        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BadPassCount.selector);
        craps.applyCrapsPasses(start, 0, false);
    }

    /// @dev The two lanes are separate inventories: high credits cannot fund normal days.
    function test_theTwoLanesDoNotSubstituteForEachOther() public {
        vm.prank(ContractAddresses.GAME);
        craps.deliverPasses(alice, 0, 3);
        uint24 start = _today() + 2;

        vm.prank(alice);
        vm.expectRevert();
        craps.applyCrapsPasses(start, 1, false);

        vm.prank(alice);
        craps.applyCrapsPasses(start, 2, true);
        assertEq(craps.dayStateOf(start, alice), craps.DAY_SEATED(), "the high run did not take");
        assertTrue(craps.daySeatIsHigh(start, alice), "the high run did not seat in the high lane");
    }

    // ── Buying a future day outright ────────────────────────────────────────

    /// @dev The price is FIXED and paid up front, per day, in one burn.
    function test_futureDaysBurnTheFixedPriceOnce() public {
        uint24 start = _today() + 1;
        uint256 before_ = flip.burned(alice);

        vm.prank(alice);
        craps.buyFutureCrapsDays(start, 3, false);

        assertEq(flip.burned(alice) - before_, 3 * craps.NORMAL_FUTURE_DAY_PRICE(), "the burn is not the fixed price");
        for (uint24 d = start; d < start + 3; ++d) {
            assertEq(craps.dayStateOf(d, alice), craps.DAY_SEATED(), "a bought day is unreserved");
        }
        (uint256 n, uint256 h) = craps.passCreditsOf(alice);
        assertEq(n + h, 0, "buying days touched the credit lanes");
    }

    /// @dev A HIGH day costs its own price, and it is not nineteen normals — the two are
    ///      independent constants and must stay that way.
    function test_theHighPriceIsItsOwnConstant() public {
        uint24 start = _today() + 1;
        uint256 before_ = flip.burned(alice);
        vm.prank(alice);
        craps.buyFutureCrapsDays(start, 1, true);
        assertEq(flip.burned(alice) - before_, craps.HIGH_FUTURE_DAY_PRICE(), "the high day burned the wrong price");
        assertEq(craps.HIGH_FUTURE_DAY_PRICE(), 450_000 ether, "the high price moved");
        assertEq(craps.NORMAL_FUTURE_DAY_PRICE(), 25_000 ether, "the normal price moved");
    }

    /// @dev A REJECTED RANGE COSTS NOTHING. The burn and the earlier days of the run unwind with
    ///      the rejection, so an attempt that cannot complete is free apart from its gas.
    function test_aRejectedRangeBurnsNothing() public {
        uint24 start = _today() + 1;
        vm.prank(alice);
        craps.buyFutureCrapsDays(start + 2, 1, false);

        uint256 before_ = flip.burned(alice);
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.DayNotReservable.selector);
        craps.buyFutureCrapsDays(start, 5, false);
        assertEq(flip.burned(alice), before_, "a rejected range still burned");
        assertEq(craps.dayStateOf(start, alice), 0, "a rejected range still wrote its first day");
    }

    /// @dev A DAY IS PER PLAYER. Two holders may each reserve the same day — they are two seats in
    ///      the same seven battles, exactly as two paid entrants would be.
    function test_twoPlayersMayReserveTheSameDay() public {
        uint24 start = _today() + 1;
        vm.prank(alice);
        craps.buyFutureCrapsDays(start, 1, false);
        vm.prank(bob);
        craps.buyFutureCrapsDays(start, 1, true);

        assertEq(craps.dayStateOf(start, alice), craps.DAY_SEATED(), "alice lost her day");
        assertEq(craps.dayStateOf(start, bob), craps.DAY_SEATED(), "bob could not take the same day");
        assertFalse(craps.daySeatIsHigh(start, alice), "alice's ordinary day joined the high lane");
        assertTrue(craps.daySeatIsHigh(start, bob), "bob's high day did not");
        // The low half is the seat count; bob's high seat also stands in the upper half.
        assertEq(uint32(craps.dayTicketsOf(start)), 2, "the day did not take both seats");
        assertEq(craps.dayTicketsOf(start) >> 32, 1, "only bob's seat belongs to the high lane");
    }

    /// @dev A PASS-FUNDED and a PREPAID reservation of the same kind are the SAME BYTE. Nothing
    ///      downstream may be able to tell which way a day was funded, or the settlement path
    ///      would have two shapes where it should have one.
    function test_fundingLeavesNoMarkOnTheDay() public {
        uint24 start = _today() + 1;
        vm.prank(ContractAddresses.GAME);
        craps.deliverPasses(alice, 1, 0);

        vm.prank(bob);
        craps.buyFutureCrapsDays(start, 1, false);

        assertEq(
            craps.dayStateOf(start, alice),
            craps.dayStateOf(start, bob),
            "a pass-funded day and a bought one are distinguishable"
        );
        assertEq(
            craps.daySeatIsHigh(start, alice),
            craps.daySeatIsHigh(start, bob),
            "the two fundings landed in different lanes"
        );
    }

    // ── The seat a commitment buys ──────────────────────────────────────────

    /// @dev THE COMMITMENT IS THE SEAT. A future day is not a claim to be redeemed later — the
    ///      whole ticket is written when the day is bought, so nothing has to be present on the
    ///      day itself and no window can strand a holder who has already paid.
    function test_aFutureDayIsSeatedTheMomentItIsBought() public {
        _warpToDayStart();
        uint24 target = _today() + 1;
        vm.prank(alice);
        craps.buyFutureCrapsDays(target, 1, false);

        assertEq(craps.dayStateOf(target, alice), craps.DAY_SEATED(), "the purchase did not seat");
        assertEq(craps.dayTicketsOf(target), 1, "the day lane did not count the seat");
        uint256 betId = (uint256(target) * craps.BONUS_SLOTS_PER_DAY() << 64) | 1;
        assertEq(craps.betOf(betId).player, alice, "the seat is not alice's");
        assertEq(craps.betOf(betId).chips, 0, "a bought day should start on a blank board");

        // Opening the day costs the holder nothing further: it was paid for at purchase.
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertEq(_today(), target, "the fixture did not land on the bought day");
        _setDailyWord(target, PLAIN_WORD);
        uint256 before_ = flip.burned(alice);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        assertEq(flip.burned(alice), before_, "opening the day charged a holder who had prepaid");
        assertEq(craps.dayStateOf(target, alice), craps.DAY_SEATED(), "the seat did not survive the open");
    }

    /// @dev A day already seated cannot be bought again, whichever door asks. One seat per address
    ///      per day is the rule, and the day state is the whole of it.
    function test_aSeatedDayCannotBeTakenTwice() public {
        _warpToDayStart();
        uint24 target = _today() + 1;
        vm.prank(alice);
        craps.buyFutureCrapsDays(target, 1, false);

        vm.prank(alice);
        vm.expectRevert(CrapsBattle.DayNotReservable.selector);
        craps.buyFutureCrapsDays(target, 1, false);

        vm.prank(ContractAddresses.GAME);
        assertEq(craps.deliverPasses(alice, 1, 0), 0, "a delivery double-booked a seated day");
        assertEq(craps.dayTicketsOf(target), 1, "the day took a second seat for one address");
    }

    /// @dev A HIGH day runs at the TARGET DAY'S OWN DRAW. The multiple is never stored — entry is
    ///      binary, so a high seat is flagged and settlement reads the size off the window — which
    ///      is exactly what lets the seat be written before the day has a word at all.
    function test_aHighReservationRunsTheTargetDaysOwnMultiple() public {
        _warpToDayStart();
        uint24 target = _today() + 1;
        vm.prank(alice);
        craps.buyFutureCrapsDays(target, 1, true);
        assertTrue(craps.daySeatIsHigh(target, alice), "the high purchase did not seat in the high lane");
        assertEq(craps.dayTicketsOf(target) >> 32, 1, "the seat did not join the day's high field");
        // Unknowable at purchase: the day has no word yet, so it has no multiple yet either.
        assertEq(craps.highMultForDay(target), 0, "the target day already had a multiple");

        vm.warp(vm.getBlockTimestamp() + 1 days);
        // A word whose draw is the HUNDRED tail — not knowable when the day was bought.
        uint256 tail;
        for (uint256 i = 1; i < 500 && tail == 0; ++i) {
            uint256 w = uint256(keccak256(abi.encode("tail", i)));
            if (craps.highMultOfWord(w) == 100) tail = w;
        }
        assertGt(tail, 0, "no word drew the tail");
        _setDailyWord(target, tail);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();

        assertEq(craps.highMultForDay(target), 100, "the day did not draw the tail");
        assertTrue(craps.daySeatIsHigh(target, alice), "the seat left the high lane");
    }

    /// @dev A SEATED DAY BLOCKS THE PAID DOORS. Its holder has already paid for the day; letting
    ///      them buy it again would take a second payment for one seat.
    function test_aReservationBlocksThePaidWholeDayEntry() public {
        _warpToDayStart();
        uint24 target = _today() + 1;
        vm.prank(alice);
        craps.buyFutureCrapsDays(target, 1, false);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _setDailyWord(target, PLAIN_WORD);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();

        vm.prank(alice);
        vm.expectRevert(CrapsBattle.AlreadyInBonus.selector);
        craps.enterBonusDay(_seven(), 1);

        // And a single window of that day is barred too — the seat is a claim on all seven.
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.AlreadyInBonus.selector);
        craps.enterBonusBattle(1, _seven(), 1);
    }

    /// @dev MISSING PERIOD ZERO COSTS THE HOLDER NOTHING. There is no redemption window to be
    ///      present for: a day bought in advance plays whether or not its holder ever shows up,
    ///      and a crank that opens the day late cannot strand what was already paid for.
    function test_aBoughtDayPlaysEvenWhenPeriodZeroIsMissed() public {
        _warpToDayStart();
        uint24 target = _today() + 1;
        vm.prank(alice);
        craps.buyFutureCrapsDays(target, 1, false);
        uint256 spent = flip.burned(alice);

        // Into the target day, and PAST the whole-day lane before the day is ever opened.
        vm.warp(vm.getBlockTimestamp() + 1 days + craps.BONUS_PERIOD() + 1);
        assertEq(_today(), target, "the fixture did not land on the bought day");
        _setDailyWord(target, PLAIN_WORD);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();

        assertEq(craps.dayStateOf(target, alice), craps.DAY_SEATED(), "a late open dropped the seat");
        assertEq(craps.dayTicketsOf(target), 3, "the day lost the prepaid seat or the house bodies");
        assertEq(flip.burned(alice), spent, "the holder paid twice for one day");
    }
}
