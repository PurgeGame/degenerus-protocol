// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsViews} from "./CrapsViews.sol";
import {Vm} from "forge-std/Vm.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract CursorHarness is CrapsViews {
    function _daySlotOfPub(uint24 day) public pure returns (uint256) {
        return uint256(day) * BONUS_SLOTS_PER_DAY;
    }
}

/// @title The scheduled cursor
/// @notice One persistent pointer names the oldest scheduled slot still owing work, and
///         `keepScheduled` does the next piece of it. The old keeper looked only at the most
///         recently closed window, so the daily event — armed in its fifteen-minute lead, worded
///         later — fell behind the rewarded crank forever. This suite is that guarantee, from
///         every angle the clock and the batches can attack it.
contract CrapsScheduledCursorTest is CrapsPins {
    CursorHarness internal craps;

    uint256 internal constant PLAIN_WORD = 40 << 8;
    uint256 internal constant PER = 1;
    uint32 internal constant SEVEN = 4 | (uint32(3) << 9);

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        _installPins();
        craps = new CursorHarness();
        // The deployment day is a Craps warm-up day with no windows; every fixture plays
        // from genesis + 1, the first day the table opens.
        vm.warp(block.timestamp + 1 days);
        _setIndex(4);
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
    }

    // ════════════════════════════════════════════════════════════════════════
    // A. The cursor's life
    // ════════════════════════════════════════════════════════════════════════

    /// @dev THE CURSOR IS BORN IN THE CONSTRUCTOR, pointing at genesis + 1: the deployment day is
    ///      a warm-up day with no windows, marked consumed at birth, so the first owed slot is
    ///      tomorrow's separator and nothing can fall behind initialization.
    function test_theCursorIsBornAtGenesisPlusOne() public {
        CursorHarness fresh = new CursorHarness();
        uint24 genesis = fresh.currentDayIndex();
        assertEq(fresh.keeperSlot(), uint64(fresh._daySlotOfPub(genesis + 1)), "the cursor was not born at tomorrow");

        // Genesis is consumed: the Game's open hook is a no-op on the warm-up day, and the
        // cursor stands in front of tomorrow claiming nothing.
        vm.prank(ContractAddresses.GAME);
        fresh.openBonusDay();
        assertEq(fresh.boostBudgetOf(genesis), 0, "the warm-up day opened windows");
        (bool progressed,) = fresh.keepScheduled(type(uint64).max);
        assertFalse(progressed, "the cursor claimed progress on the warm-up day");
    }

    /// @dev THE SEPARATOR IS CROSSED, NEVER PROBED. The fixture clock sits an hour into the day,
    ///      so period 0's window has already closed: one call hops the remainder-zero slot AND
    ///      shuts that window, in cursor order. The call after it is a poll — the armed field is
    ///      wordless, and standing in front of it claims nothing.
    function test_theCursorCrossesTheSeparatorAndArmsTheClosedOpener() public {
        _openDay();
        uint24 today = craps.currentDayIndex();
        (bool progressed, uint64 slot) = craps.keepScheduled(type(uint64).max);
        assertTrue(progressed, "the hop-and-arm was not progress");
        assertEq(slot, uint64(craps._daySlotOfPub(today)) + 1, "the cursor is not holding the armed opener");
        assertGt(craps.slotIndexOf(slot), 0, "the closed opener was not armed in the same call");

        // And AGAIN is a poll: wordless, no progress, no bounty.
        (progressed,) = craps.keepScheduled(type(uint64).max);
        assertFalse(progressed, "polling a wordless armed field claimed progress");
    }

    /// @dev THE WHOLE LIFECYCLE OF ONE WINDOW, driven only through `keepScheduled`: waits while
    ///      live, arms at the close (zero budget suffices — the arm is the time-critical piece),
    ///      waits wordless without advancing or claiming progress, settles when the word lands,
    ///      and crosses only on finalization.
    function test_oneWindowsLifeUnderTheCursor() public {
        _openDay();
        _seat(alice, PER);
        _seat(bob, PER);

        _warpPastClose(PER);
        // ZERO BUDGET, and the first call still hops the separator and shuts the closed opener —
        // the arm is the time-critical piece and costs no settlement.
        (bool progressed, uint64 slot) = craps.keepScheduled(0);
        assertTrue(progressed, "the arm at zero budget did not count as progress");
        uint64 winSlot = _slotAt(PER);
        // Period 0's window armed first (oldest); drive until the window under test is armed.
        for (uint256 i = 0; i < 8 && craps.slotIndexOf(winSlot) == 0; ++i) {
            uint48 pending = craps.slotIndexOf(craps.keeperSlot());
            if (pending != 0 && craps.wordAt(pending - 1) == 0) {
                _setIndex(pending - 1);
                _setWord(pending - 1, uint256(keccak256(abi.encode("life", i))));
            }
            craps.keepScheduled(type(uint64).max);
        }
        assertGt(craps.slotIndexOf(winSlot), 0, "the cursor never armed the window under test");

        // WORDLESS: stopped, unadvanced, unpaid.
        uint64 at = craps.keeperSlot();
        assertEq(at, winSlot, "the cursor is not standing on the armed window");
        (progressed, slot) = craps.keepScheduled(type(uint64).max);
        assertFalse(progressed, "a wordless armed field claimed progress");
        assertEq(slot, winSlot, "a wordless armed field advanced the cursor");

        // The word lands; the field settles and the cursor crosses.
        uint48 index = craps.slotIndexOf(winSlot) - 1;
        _setIndex(index);
        _setWord(index, uint256(keccak256("life-word")));
        (progressed,) = craps.keepScheduled(type(uint64).max);
        assertTrue(progressed, "settling the field was not progress");
        assertTrue(craps.battleOf(craps.keyOfSlot(winSlot)).finalized, "the field did not finalize");
        assertGt(craps.keeperSlot(), winSlot, "a finalized field did not release the cursor");
    }

    /// @dev A PARTIAL FIELD RESUMES ON THE SAME SLOT ACROSS MIDNIGHT. The wall clock has no vote:
    ///      the cursor is storage, and the seat cursor it left behind is where the walk resumes.
    function test_aPartialFieldResumesTheSameSlotAcrossMidnight() public {
        _openDay();
        for (uint256 i = 0; i < 24; ++i) {
            _seat(address(uint160(uint256(keccak256(abi.encode("deep", i))))), PER);
        }
        uint64 winSlot = _slotAt(PER);
        _warpPastClose(PER);
        _driveCursorTo(winSlot);

        uint48 index = craps.slotIndexOf(winSlot) - 1;
        _setIndex(index);
        _setWord(index, uint256(keccak256("midnight")));

        // A small budget settles part of the field.
        (bool progressed,) = craps.keepScheduled(160);
        assertTrue(progressed, "the partial batch was not progress");
        uint64 walked = craps.bonusCursorOf(winSlot);
        assertGt(walked, 0, "no seats settled");
        assertLt(walked, craps.battleOf(craps.keyOfSlot(winSlot)).entrants, "the fixture field settled whole");
        assertEq(craps.keeperSlot(), winSlot, "a partial field released the cursor");

        // MIDNIGHT. The cursor still points at the same slot and the walk resumes at walked+1.
        vm.warp(block.timestamp + 1 days);
        assertEq(craps.keeperSlot(), winSlot, "midnight moved the cursor");
        (progressed,) = craps.keepScheduled(type(uint64).max);
        assertTrue(progressed, "the resumed batch was not progress");
        assertGt(craps.bonusCursorOf(winSlot), walked, "the walk did not resume past its seat cursor");
    }

    /// @dev EXTERNAL HELP IS DETECTED, NEVER WEDGED ON — and never double-paid. A window armed
    ///      and fully settled through the permissionless doors is one legitimate cursor advance;
    ///      the pot paid exactly once.
    function test_anExternallySettledWindowIsCrossedWithoutASecondPayout() public {
        _openDay();
        _seat(alice, PER);
        _warpPastClose(PER);
        _driveCursorTo(_slotAt(PER));
        uint64 winSlot = _slotAt(PER);

        // Somebody else finishes the whole field directly.
        uint48 index = craps.slotIndexOf(winSlot) - 1;
        _setIndex(index);
        _setWord(index, uint256(keccak256("external")));
        vm.recordLogs();
        craps.resolveSlot(winSlot, WHOLE_FIELD);
        uint256 pots = _countSig(vm.getRecordedLogs(), keccak256("CrapsBattlePaid(uint256,bytes32,address,uint256)"));
        assertTrue(craps.battleOf(craps.keyOfSlot(winSlot)).finalized, "the external settle did not finish");

        // The cursor crosses it as done work — no second settlement, no second pot.
        vm.recordLogs();
        (bool progressed, uint64 slot) = craps.keepScheduled(type(uint64).max);
        assertTrue(progressed, "crossing externally-done work is one-time progress");
        assertGt(slot, winSlot, "the cursor did not cross the finished window");
        assertEq(
            _countSig(vm.getRecordedLogs(), keccak256("CrapsBattlePaid(uint256,bytes32,address,uint256)")),
            0,
            "crossing a finished field paid a second pot"
        );
        assertLe(pots, 1, "the external settle itself paid more than one pot");
    }

    // ════════════════════════════════════════════════════════════════════════
    // B. Lapsed days
    // ════════════════════════════════════════════════════════════════════════

    /// @dev A DAY THE ADVANCE NEVER OPENED IS SWEPT, NOT REPLAYED: every reservation on it comes
    ///      back as the pass credit it was, exactly once, and the cursor steps over the whole
    ///      day — separator and windows — in one move.
    function test_aLapsedDaysReservationsComeBackAsCredits() public {
        _openDay();
        uint24 dayA = craps.currentDayIndex();
        _settleWholeDay(dayA);

        // Reservations on the two days after A: alice normal, bob high.
        vm.prank(ContractAddresses.GAME);
        craps.creditPasses(alice, 1, 0);
        vm.prank(ContractAddresses.GAME);
        craps.creditPasses(bob, 0, 1);
        vm.prank(alice);
        craps.applyCrapsPasses(dayA + 1, 1, false);
        vm.prank(bob);
        craps.applyCrapsPasses(dayA + 1, 1, true);
        (uint256 aN,) = craps.passCreditsOf(alice);
        (, uint256 bH) = craps.passCreditsOf(bob);
        assertEq(aN, 0, "alice's credit was not spent on the reservation");
        assertEq(bH, 0, "bob's credit was not spent on the reservation");

        // THE STALL: days A+1 and A+2 never open. The clock lands on A+3, which does.
        vm.warp(block.timestamp + 3 days);
        _setDailyWord(dayA + 3, PLAIN_WORD);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        assertEq(craps.boostBudgetOf(dayA + 1), 0, "the stalled day opened");

        // The cursor sweeps A+1 (two seats), then A+2 (none), then crosses into A+3 — a
        // completed sweep is a call's one expensive action, so the two dead days take two calls.
        vm.recordLogs();
        (bool progressed,) = craps.keepScheduled(type(uint64).max);
        assertTrue(progressed, "the first sweep was not progress");
        (progressed,) = craps.keepScheduled(type(uint64).max);
        assertTrue(progressed, "the second sweep was not progress");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (aN,) = craps.passCreditsOf(alice);
        (, bH) = craps.passCreditsOf(bob);
        assertEq(aN, 1, "alice's lapsed reservation did not come back as a normal credit");
        assertEq(bH, 1, "bob's lapsed reservation did not come back as a HIGH credit");
        assertEq(_countSig(logs, keccak256("CrapsDayLapsed(uint24,uint64)")), 2, "both dead days did not lapse");
        assertGe(craps.keeperSlot(), uint64(craps._daySlotOfPub(dayA + 3)), "the cursor did not cross the dead days");

        // ONCE. Driving the cursor further never re-credits.
        craps.keepScheduled(type(uint64).max);
        (aN,) = craps.passCreditsOf(alice);
        assertEq(aN, 1, "a lapsed reservation was refunded twice");
    }

    /// @dev A PARTIAL SWEEP IS PROGRESS. The rewarded crank reverts a no-progress call as
    ///      NoWork, and that revert would roll the refunds back out — so a sweep that credited
    ///      anybody must say so, and the follow-up call finishes the day from where it stopped.
    function test_aPartialSweepReportsProgressSoItsRefundsSurvive() public {
        _openDay();
        uint24 dayA = craps.currentDayIndex();
        _settleWholeDay(dayA);
        vm.prank(ContractAddresses.GAME);
        craps.creditPasses(alice, 1, 0);
        vm.prank(ContractAddresses.GAME);
        craps.creditPasses(bob, 1, 0);
        vm.prank(alice);
        craps.applyCrapsPasses(dayA + 1, 1, false);
        vm.prank(bob);
        craps.applyCrapsPasses(dayA + 1, 1, false);

        vm.warp(block.timestamp + 2 days);
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();

        // A budget worth exactly one refund: the sweep stops mid-day and MUST report progress.
        (bool progressed,) = craps.keepScheduled(8);
        assertTrue(progressed, "a partial sweep denied its own refunds");
        (uint256 aN,) = craps.passCreditsOf(alice);
        (uint256 bN,) = craps.passCreditsOf(bob);
        assertEq(aN + bN, 1, "the one-seat budget did not refund exactly one seat");

        // And the next call finishes the day from where the sweep stopped.
        (progressed,) = craps.keepScheduled(type(uint64).max);
        assertTrue(progressed, "finishing the sweep was not progress");
        (aN,) = craps.passCreditsOf(alice);
        (bN,) = craps.passCreditsOf(bob);
        assertEq(aN + bN, 2, "the finished sweep did not refund the rest");
    }

    /// @dev TODAY IS NEVER SWEPT. An un-opened current day is the advance's to open, and the
    ///      cursor waits in front of it claiming nothing.
    function test_theCursorNeverSweepsToday() public {
        _openDay();
        _settleWholeDay(craps.currentDayIndex());
        vm.warp(block.timestamp + 1 days);
        // Today's word exists but openBonusDay has not run.
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
        (bool progressed, uint64 slot) = craps.keepScheduled(type(uint64).max);
        assertEq(slot, uint64(craps._daySlotOfPub(craps.currentDayIndex())), "the cursor is not at today's separator");
        assertFalse(progressed && craps.boostBudgetOf(craps.currentDayIndex()) == 0, "the cursor touched an unopened today");
    }

    // ════════════════════════════════════════════════════════════════════════
    // C. The comparator's money clamp
    // ════════════════════════════════════════════════════════════════════════

    /// @dev SATURATION, NOT WRAP. At and past the 44-bit field a bigger return can never rank
    ///      worse — the clamp holds the component at the ceiling instead of folding it small.
    function test_theWinningsComponentSaturatesRatherThanWrapping() public view {
        uint256 mask = 0xFFFFFFFFFFF;
        assertEq(craps.wonComponentOf((mask - 1) * 1 ether), mask - 1, "below the field moved");
        assertEq(craps.wonComponentOf(mask * 1 ether), mask, "the field's own top moved");
        assertEq(craps.wonComponentOf((mask + 1) * 1 ether), mask, "one past the field did not saturate");
        assertEq(craps.wonComponentOf(type(uint128).max), mask, "a huge return did not saturate");
        // Monotone across the boundary: more money is never a worse component.
        assertGe(
            craps.wonComponentOf((mask + 1) * 1 ether),
            craps.wonComponentOf(mask * 1 ether),
            "the clamp broke monotonicity"
        );
    }

    // ════════════════════════════════════════════════════════════════════════
    // Fixtures
    // ════════════════════════════════════════════════════════════════════════

    function _dayStart() internal view returns (uint256) {
        return block.timestamp - ((block.timestamp - 82_620) % 1 days);
    }

    function _closeOf(uint256 period) internal view returns (uint256) {
        if (period + 1 == craps.BONUS_PERIODS_PER_DAY()) return 1 days - craps.EVENT_LEAD();
        uint256 base = period == 0 ? craps.BONUS_EVENT_CLOSE() : period * craps.BONUS_PERIOD();
        return base + craps.BONUS_CLOCK_ALIGN();
    }

    function _warpPastClose(uint256 period) internal {
        vm.warp(_dayStart() + _closeOf(period));
    }

    function _openDay() internal {
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
    }

    function _slotAt(uint256 period) internal view returns (uint64) {
        (uint24 day,,) = craps.currentBonusSlot();
        return uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + period + 1);
    }

    function _seat(address who, uint256 period) internal {
        game.setScore(who, craps.SYBIL_SCORE_FLOOR());
        vm.prank(who);
        craps.enterBonusBattle(period, SEVEN, 1);
    }

    /// @dev Drive the cursor forward — feeding each armed slot its word — until it stands on
    ///      `target` with `target` armed.
    function _driveCursorTo(uint64 target) internal {
        for (uint256 i = 0; i < 24; ++i) {
            uint64 at = craps.keeperSlot();
            if (at == target && craps.slotIndexOf(target) != 0) return;
            uint48 pending = craps.slotIndexOf(at);
            if (pending != 0 && craps.wordAt(pending - 1) == 0 && at != target) {
                _setIndex(pending - 1);
                _setWord(pending - 1, uint256(keccak256(abi.encode("drive", i))));
            }
            craps.keepScheduled(type(uint64).max);
        }
        revert("the cursor never reached the target");
    }

    /// @dev Settle every window of `day` through the cursor, feeding words as they are owed.
    function _settleWholeDay(uint24 day) internal {
        uint64 pastAll = uint64(craps._daySlotOfPub(day)) + uint64(craps.BONUS_SLOTS_PER_DAY());
        vm.warp(_dayStart() + 1 days - 1); // inside the event lead: every window has closed
        for (uint256 i = 0; i < 40; ++i) {
            if (craps.keeperSlot() >= pastAll) return;
            uint64 at = craps.keeperSlot();
            uint48 pending = craps.slotIndexOf(at);
            if (pending != 0 && craps.wordAt(pending - 1) == 0) {
                _setIndex(pending - 1);
                _setWord(pending - 1, uint256(keccak256(abi.encode("whole", day, i))));
            }
            craps.keepScheduled(type(uint64).max);
        }
        revert("the day never settled whole");
    }

    function _countSig(Vm.Log[] memory logs, bytes32 sig) internal pure returns (uint256 n) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] == sig) ++n;
        }
    }
}
