// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Craps} from "../../contracts/Craps.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {Vm} from "forge-std/Vm.sol";
import {stdError} from "forge-std/Test.sol";

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

        // Over the ceiling: the excess is silently clamped and the call still returns — the cap
        // is unreachable by any real award, so nothing here is worth a log of its own.
        vm.prank(ContractAddresses.GAME);
        craps.deliverPasses(alice, 10, 0);
        (n,) = craps.passCreditsOf(alice);
        assertEq(n, max, "the lane did not saturate at its ceiling");
    }

    // ── The board a reservation names ───────────────────────────────────────

    /// @dev Restated for `expectEmit`; matched by topics and data, not by declaring contract.
    event CrapsSlipPlaced(address indexed player, uint256 bet);

    /// @dev A seven-chip allocation in the packed shape the doors take: 4 on the pass line, 3 on
    ///      place 8 — `_seven()` as the doors see it.
    uint32 internal constant PACKED_SEVEN = 4 | (3 << 12);

    /// @dev A reservation may name its board up front, and ONE slip then serves every day of the
    ///      run: each reserved day's ticket stores the same chips, and each day's own
    ///      `CrapsSlipPlaced` carries them.
    function test_aReservationNamesOneBoardForTheWholeRun() public {
        vm.prank(ContractAddresses.GAME);
        craps.creditPasses(alice, 2, 0);
        uint24 start = _today() + 2;

        vm.prank(alice);
        craps.applyCrapsPasses(start, 2, false, PACKED_SEVEN);

        for (uint24 d = start; d < start + 2; ++d) {
            uint256 seat = craps.daySeatNumberOf(d, alice);
            uint256 betId = ((uint256(d) * craps.BONUS_SLOTS_PER_DAY()) << 64) | seat;
            assertEq(craps.betOf(betId).chips, PACKED_SEVEN, "a reserved day did not store the named board");
        }
    }

    /// @dev The bought door takes the same board the credit door does.
    function test_aBoughtRunNamesItsBoardToo() public {
        uint24 target = _today() + 1;
        uint256 daySlot = uint256(target) * craps.BONUS_SLOTS_PER_DAY();
        // The first seat on an untouched future day is seat one, so the slip event is exact.
        vm.expectEmit(address(craps));
        emit CrapsSlipPlaced(
            alice,
            uint256(PACKED_SEVEN) | (((daySlot << 64) | 1) << 32)
                | (craps.SYBIL_SCORE_FLOOR() << 190)
        );
        vm.prank(alice);
        craps.buyFutureCrapsDays(target, 1, false, PACKED_SEVEN);
        uint256 betId = (daySlot << 64) | craps.daySeatNumberOf(target, alice);
        assertEq(craps.betOf(betId).chips, PACKED_SEVEN, "the bought day did not store the named board");
    }

    /// @dev A named board is held to the very rules the live doors enforce: seven chips or none,
    ///      four to a leg, one side of the line — vetted before anything burns or debits.
    function test_aReservedBoardMustBeSevenLegalChips() public {
        vm.prank(ContractAddresses.GAME);
        craps.creditPasses(alice, 4, 0);
        uint24 start = _today() + 2;

        // Three chips are neither blank nor a full pick.
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BadRandomCount.selector);
        craps.applyCrapsPasses(start, 1, false, 3);

        // Five on one leg breaks the per-leg cap even inside seven total.
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.TooManyChipsOnALeg.selector);
        craps.applyCrapsPasses(start, 1, false, uint32(5 << 3) | 2);

        // Backing the shooter and fading them at once is refused at this door like every other.
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BoardPlaysBothSides.selector);
        craps.applyCrapsPasses(start, 1, false, uint32(4 | (3 << 27)));

        (uint256 n,) = craps.passCreditsOf(alice);
        assertEq(n, 4, "a refused board still spent a credit");

        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BadRandomCount.selector);
        craps.buyFutureCrapsDays(start, 1, false, 3);
        assertEq(flip.burned(alice), 0, "a refused board still burned the fixed price");
    }

    /// @dev The one slip serves the run, but each DAY is still its own ticket: re-spreading one
    ///      reserved day in its own period zero moves that day alone.
    function test_aReservedBoardStillAmendsDayByDay() public {
        vm.prank(ContractAddresses.GAME);
        craps.creditPasses(alice, 2, 0);
        uint24 start = _today() + 1;
        vm.prank(alice);
        craps.applyCrapsPasses(start, 2, false, PACKED_SEVEN);

        // Into the FIRST reserved day's period zero, where its slip may still be re-spread.
        _warpToDayStart();
        assertEq(_today(), start, "the fixture did not land on the first reserved day");
        uint256 firstId = ((uint256(start) * craps.BONUS_SLOTS_PER_DAY()) << 64)
            | craps.daySeatNumberOf(start, alice);
        uint32 respread = 2 | (2 << 9) | (3 << 15);
        vm.prank(alice);
        craps.amendSlip(firstId, respread);

        assertEq(craps.betOf(firstId).chips, respread, "the first day did not take the new spread");
        uint256 secondId = ((uint256(start + 1) * craps.BONUS_SLOTS_PER_DAY()) << 64)
            | craps.daySeatNumberOf(start + 1, alice);
        assertEq(craps.betOf(secondId).chips, PACKED_SEVEN, "amending one day moved its neighbour");
    }

    /// @dev A FUTURE reservation's board is its holder's to move until the day's own opener
    ///      closes: amendable days ahead (standing refreshing with it), still amendable at the
    ///      boundary — the target day's own period zero — and locked one period later, exactly
    ///      where the live ticket has always locked.
    function test_aFutureReservationsBoardAmendsUntilItsOwnOpenerCloses() public {
        _warpToDayStart();
        vm.prank(ContractAddresses.GAME);
        craps.creditPasses(alice, 1, 0);
        uint24 target = _today() + 3;
        vm.prank(alice);
        craps.applyCrapsPasses(target, 1, false, PACKED_SEVEN);
        uint256 betId = ((uint256(target) * craps.BONUS_SLOTS_PER_DAY()) << 64)
            | craps.daySeatNumberOf(target, alice);

        // Days ahead of the clock: the board moves and the standing rides with it.
        uint32 respread = 2 | (2 << 9) | (3 << 15);
        game.setScore(alice, craps.SYBIL_SCORE_FLOOR() + 3);
        vm.prank(alice);
        craps.amendSlip(betId, respread);
        assertEq(craps.betOf(betId).chips, respread, "a future day's board did not move");
        assertEq(
            craps.betOf(betId).standing,
            craps.SYBIL_SCORE_FLOOR() + 3,
            "the amendment did not refresh standing"
        );

        // Future or not, it is still nobody else's.
        vm.prank(bob);
        vm.expectRevert(CrapsBattle.NotYourBet.selector);
        craps.amendSlip(betId, PACKED_SEVEN);

        // The boundary itself — the target day's own period zero — still amends.
        vm.warp(vm.getBlockTimestamp() + 3 days);
        assertEq(_today(), target, "the fixture did not land on the target day");
        vm.prank(alice);
        craps.amendSlip(betId, PACKED_SEVEN);
        assertEq(craps.betOf(betId).chips, PACKED_SEVEN, "period zero of the day itself stopped amending");

        // One period later the day's first window has shut its door, and so has the ticket's.
        vm.warp(vm.getBlockTimestamp() + craps.BONUS_EVENT_CLOSE() + craps.BONUS_CLOCK_ALIGN() + 1);
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BetLocked.selector);
        craps.amendSlip(betId, respread);
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

    // ── Normal-to-high conversion ───────────────────────────────────────────

    bytes32 internal constant _CONVERTED_SIG = keccak256("CrapsNormalPassesConverted(address,uint256,uint256)");

    /// @dev NINETEEN NORMALS BUY ONE HIGH — the credits' own value ratio, so the conversion moves
    ///      value exactly. The retail future-day prices imply 18:1; that pair carries margins the
    ///      credits never did, and pricing off it would subsidize every conversion.
    function test_nineteenNormalsConvertToOneHigh() public {
        craps.setPassCredits(alice, 19, 0);
        vm.prank(alice);
        craps.convertNormalToHigh(1);
        (uint256 n, uint256 h) = craps.passCreditsOf(alice);
        assertEq(n, 0, "the nineteen normals were not all spent");
        assertEq(h, 1, "the high credit did not arrive");
    }

    /// @dev The handoff's own worked example: 38 normal and 4 high become 0 and 6, atomically.
    function test_thirtyEightNormalsConvertToTwoHighs() public {
        craps.setPassCredits(alice, 38, 4);
        vm.prank(alice);
        craps.convertNormalToHigh(2);
        (uint256 n, uint256 h) = craps.passCreditsOf(alice);
        assertEq(n, 0, "the two conversions did not spend all thirty-eight normals");
        assertEq(h, 6, "the high lane did not gain exactly two");
    }

    function test_aZeroConversionReverts() public {
        craps.setPassCredits(alice, 19, 0);
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BadPassCount.selector);
        craps.convertNormalToHigh(0);
    }

    /// @dev EIGHTEEN CANNOT BUY ONE. The rate is nineteen exactly, and a short balance reverts on
    ///      the debit itself with neither lane moved.
    function test_eighteenNormalsCannotBuyAHigh() public {
        craps.setPassCredits(alice, 18, 7);
        vm.prank(alice);
        vm.expectRevert(stdError.arithmeticError);
        craps.convertNormalToHigh(1);
        (uint256 n, uint256 h) = craps.passCreditsOf(alice);
        assertEq(n, 18, "a refused conversion still debited normals");
        assertEq(h, 7, "a refused conversion still credited a high");
    }

    /// @dev A SHORT MULTI-COUNT is refused whole: 37 normals cannot buy two highs, and the one
    ///      conversion they could have bought is not quietly delivered instead.
    function test_aShortBalanceConvertsNothingNotPart() public {
        craps.setPassCredits(alice, 37, 0);
        vm.prank(alice);
        vm.expectRevert(stdError.arithmeticError);
        craps.convertNormalToHigh(2);
        (uint256 n, uint256 h) = craps.passCreditsOf(alice);
        assertEq(n, 37, "a refused conversion moved the normal lane");
        assertEq(h, 0, "a refused conversion moved the high lane");
    }

    /// @dev A FULL HIGH LANE refuses the conversion BEFORE the debit — all or nothing, so an
    ///      overflow cannot burn normals for credits that were never banked.
    function test_aFullHighLaneRevertsWithoutDebitingNormals() public {
        craps.setPassCredits(alice, 19, type(uint32).max);
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.PassLaneFull.selector);
        craps.convertNormalToHigh(1);
        (uint256 n, uint256 h) = craps.passCreditsOf(alice);
        assertEq(n, 19, "an overflowing conversion still debited normals");
        assertEq(h, type(uint32).max, "the full lane moved");
    }

    /// @dev ONE LOG AND ONLY ONE. Both lane deltas live in the conversion event; a
    ///      `CrapsPassesCredited` alongside it would hand an indexer the high addition twice.
    function test_aConversionEmitsExactlyOneCanonicalLog() public {
        craps.setPassCredits(alice, 57, 0);
        vm.recordLogs();
        vm.prank(alice);
        craps.convertNormalToHigh(3);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "a conversion logged other than once");
        assertEq(logs[0].topics[0], _CONVERTED_SIG, "the one log is not the conversion event");
        assertEq(address(uint160(uint256(logs[0].topics[1]))), alice, "the log named another player");
        (uint256 spent, uint256 received) = abi.decode(logs[0].data, (uint256, uint256));
        assertEq(spent, 57, "the log misstates the normals spent");
        assertEq(received, 3, "the log misstates the highs received");
    }

    /// @dev ONLY BANKED CREDITS ARE REACHABLE. A pass already committed to a day lives in that
    ///      day's seat word, and converting the remaining bank neither touches the reservation
    ///      nor claws the committed pass back.
    function test_aConversionCannotReachACommittedReservation() public {
        craps.setPassCredits(alice, 20, 0);
        uint24 target = _today() + 2;
        vm.prank(alice);
        craps.applyCrapsPasses(target, 1, false);
        assertEq(craps.dayStateOf(target, alice), craps.DAY_SEATED(), "the fixture's reservation did not land");

        vm.prank(alice);
        craps.convertNormalToHigh(1);
        (uint256 n, uint256 h) = craps.passCreditsOf(alice);
        assertEq(n, 0, "the conversion did not spend the remaining bank");
        assertEq(h, 1, "the conversion did not bank the high");
        assertEq(craps.dayStateOf(target, alice), craps.DAY_SEATED(), "a conversion disturbed a reserved day");
        assertEq(craps.daySeatIsHigh(target, alice), false, "a conversion re-denominated a reserved day");
    }

    /// @dev NOTHING BURNS, MINTS OR MOVES COINFLIP MONEY. A conversion is a pure re-denomination
    ///      of banked credits.
    function test_aConversionTouchesNoOutsideLedger() public {
        craps.setPassCredits(alice, 19, 0);
        uint256 burnedBefore = flip.burned(alice);
        uint256 creditsBefore = coinflip.credits();
        vm.prank(alice);
        craps.convertNormalToHigh(1);
        assertEq(flip.burned(alice), burnedBefore, "a conversion burned FLIP");
        assertEq(coinflip.credits(), creditsBefore, "a conversion moved coinflip credit");
    }
}

/// @title The protocol-award pass split — the deterministic half-to-passes formula
/// @notice Half of an eligible protocol award is targeted at pass credits; only WHOLE passes are
///         issued, and every fractional remainder, cap excess and saturation refusal stays in the
///         winner's liquid FLIP in the same transaction. The formula is a pure function of the
///         award — no word, no entropy, no coin toss — and these tests grade it boundary by
///         boundary through the shipped `_splitAward`, the same code every payout site calls.
contract CrapsAwardSplitTest is CrapsPins {
    CrapsViews internal craps;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    bytes32 internal constant KEY = keccak256("split-under-test");
    bytes32 internal constant _CREDITED_SIG = keccak256("CrapsPassesCredited(address,bool,uint256)");
    bytes32 internal constant _SPLIT_SIG =
        keccak256("CrapsProtocolAwardSplit(bytes32,address,uint8,uint256,uint256)");

    uint256 internal N;
    uint256 internal H;

    function setUp() public {
        _installPins();
        craps = new CrapsViews();
        vm.warp(block.timestamp + 1 days);
        _setIndex(4);
        N = craps.NORMAL_PASS_VALUE();
        H = craps.HIGH_PASS_VALUE();
    }

    /// @dev One split, graded whole: the banked value, the resulting credits, and the exact
    ///      conservation `liquid + banked == gross` that every case below must close.
    function _grade(uint256 gross, uint256 wantNormal, uint256 wantHigh) internal {
        address player = makeAddr(string(abi.encodePacked("grade", gross)));
        uint256 banked = craps.splitAward(KEY, player, 1, gross);
        (uint256 n, uint256 h) = craps.passCreditsOf(player);
        assertEq(n, wantNormal, "the normal pass count is wrong");
        assertEq(h, wantHigh, "the high pass count is wrong");
        assertEq(banked, wantNormal * N + wantHigh * H, "the banked value is not the credited passes' value");
        // The liquid remainder is `gross - banked` by construction; what the identity adds is
        // that the banked side never exceeds the half-award target and never mixes denominations.
        assertLe(banked, gross / 2, "the pass slice overran the half-award target");
        assertTrue(wantNormal == 0 || wantHigh == 0, "one award mixed denominations");
    }

    /// @dev Below one whole pass nothing banks: the entire award stays liquid, with no log.
    function test_underOneUnitSplitsNothing() public {
        vm.recordLogs();
        assertEq(craps.splitAward(KEY, alice, 1, 0), 0, "an empty award banked something");
        assertEq(craps.splitAward(KEY, alice, 1, 2 * N - 2), 0, "a sub-unit budget banked a pass");
        assertEq(vm.getRecordedLogs().length, 0, "a splitless award still logged");
        (uint256 n, uint256 h) = craps.passCreditsOf(alice);
        assertEq(n + h, 0, "a splitless award still banked credits");
    }

    /// @dev `A = 2N` is the smallest converting award: one normal pass, exactly N liquid.
    function test_theSmallestAwardBanksOneNormal() public {
        _grade(2 * N, 1, 0);
    }

    /// @dev EXACTLY the switch: a 20N budget is still NORMAL — twenty normal passes, never one
    ///      high — and one wei more flips the whole portion to a single high pass.
    function test_theDenominationCliffIsStrict() public {
        _grade(40 * N, 20, 0);
        _grade(40 * N + 2, 0, 1);
    }

    /// @dev The handoff's worked example: a 1,000,000 FLIP award has a 500,000 target, above
    ///      456,000 — ONE high pass worth 433,200 and 566,800 liquid. Not twenty-one normals,
    ///      and no random second high.
    function test_theWorkedMillionFlipExample() public {
        uint256 gross = 1_000_000 ether;
        uint256 banked = craps.splitAward(KEY, alice, 2, gross);
        (uint256 n, uint256 h) = craps.passCreditsOf(alice);
        assertEq(n, 0, "the high award issued normals");
        assertEq(h, 1, "the award did not bank exactly one high pass");
        assertEq(banked, 433_200 ether, "the pass value is not one high pass");
        assertEq(gross - banked, 566_800 ether, "the liquid change is not the remainder");
    }

    /// @dev Fractional remainders return as FLIP exactly, in both denominations.
    function test_fractionalRemaindersStayLiquid() public {
        _grade(2 * N + 12_345, 1, 0);
        _grade(50 * N + 7, 0, 1);
    }

    /// @dev The thirty-high boundary holds and the thirty-first is refused: the cap floors the
    ///      COUNT, and the capped units' value stays liquid rather than vanishing.
    function test_theThirtyHighCap() public {
        _grade(60 * H, 0, 30);
        _grade(62 * H + 4, 0, 30);
    }

    /// @dev A SATURATED LANE CANNOT DELETE VALUE. What the lane refuses never leaves the liquid
    ///      side: a full lane banks nothing, a partial one banks only what fits, and the banked
    ///      figure prices off the ACTUAL credit either way.
    function test_aFullOrPartialLaneOnlyBanksWhatFits() public {
        craps.setPassCredits(alice, type(uint32).max, 0);
        vm.recordLogs();
        assertEq(craps.splitAward(KEY, alice, 1, 40 * N), 0, "a full lane still charged the award");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != _SPLIT_SIG, "a split that banked nothing still announced one");
        }

        craps.setPassCredits(bob, type(uint32).max - 5, 0);
        uint256 banked = craps.splitAward(KEY, bob, 1, 40 * N);
        assertEq(banked, 5 * N, "a partial lane did not price off the actual credit");
        (uint256 n,) = craps.passCreditsOf(bob);
        assertEq(n, type(uint32).max, "the partial credit did not top the lane off");
    }

    /// @dev NO WORD, NO ENTROPY: the same award splits identically whatever the day's word says.
    function test_theSplitIsDeterministicAcrossWords() public {
        uint256 gross = 3 * N + 777;
        _setDailyWord(craps.currentDayIndex(), uint256(keccak256("word-one")));
        uint256 a = craps.splitAward(KEY, alice, 1, gross);
        _setDailyWord(craps.currentDayIndex(), uint256(keccak256("word-two")));
        uint256 b = craps.splitAward(KEY, bob, 1, gross);
        assertEq(a, b, "two words split one award differently");
        (uint256 na,) = craps.passCreditsOf(alice);
        (uint256 nb,) = craps.passCreditsOf(bob);
        assertEq(na, nb, "two words banked different counts");
        assertEq(na, 1, "the award did not bank its one whole pass");
    }

    /// @dev THE LOG ORDER IS THE CONTRACT: `CrapsPassesCredited` lands immediately before the
    ///      split event, carrying the denomination and count; the split carries gross and liquid.
    ///      An indexer correlates the pair by position, so the pair — and nothing else — is what
    ///      one converting award may emit.
    function test_theSplitLogsCreditThenSplitAndNothingElse() public {
        uint256 gross = 2 * N + 9;
        vm.recordLogs();
        craps.splitAward(KEY, alice, 4, gross);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2, "one converting award logged other than twice");

        assertEq(logs[0].topics[0], _CREDITED_SIG, "the first log is not the pass credit");
        assertEq(address(uint160(uint256(logs[0].topics[1]))), alice, "the credit named another player");
        (bool high, uint256 count) = abi.decode(logs[0].data, (bool, uint256));
        assertFalse(high, "a normal award credited the high lane");
        assertEq(count, 1, "the credit misstates the count");

        assertEq(logs[1].topics[0], _SPLIT_SIG, "the second log is not the split");
        assertEq(logs[1].topics[1], KEY, "the split named another battle");
        assertEq(address(uint160(uint256(logs[1].topics[2]))), alice, "the split named another player");
        assertEq(uint256(logs[1].topics[3]), 4, "the split misnamed its source");
        (uint256 g, uint256 liquid) = abi.decode(logs[1].data, (uint256, uint256));
        assertEq(g, gross, "the split misstates the gross award");
        assertEq(liquid, gross - N, "the split misstates the liquid remainder");
    }

    /// @dev TWO SOURCES NEVER POOL. A 2N main award and a 50N progressive award to the same
    ///      winner denominate independently — one normal and one high — where a pooled 52N would
    ///      have gone all high. The discriminating outcome is exactly the two-event shape.
    function test_twoAwardsToOneWinnerSplitIndependently() public {
        vm.recordLogs();
        craps.splitAward(KEY, alice, 1, 2 * N);
        craps.splitAward(KEY, alice, 4, 50 * N);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256 n, uint256 h) = craps.passCreditsOf(alice);
        assertEq(n, 1, "the main award did not bank its normal pass");
        assertEq(h, 1, "the progressive award did not bank its high pass");
        uint256 splits;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] == _SPLIT_SIG) ++splits;
        }
        assertEq(splits, 2, "two awards did not announce two independent splits");
    }
}
