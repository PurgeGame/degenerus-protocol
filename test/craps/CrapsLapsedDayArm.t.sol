// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {CrapsPins} from "./CrapsPins.sol";

contract LapseArmHarness is CrapsViews {
    function fieldOf(bytes32 key) external view returns (uint256 entrants, uint256 resolved) {
        uint256 g = _battles[key];
        return (g & _MASK32, (g >> _BG_RESOLVED_SHIFT) & _MASK32);
    }

    function stakeUnitsOf(uint64 slot) external view returns (uint256) {
        return _slotWindow(slot).stakeUnits;
    }
}

/// @dev A day the advance never opened (a VRF stall that skipped the wall day, later backfilled
///      with a word) is LAPSED to the keeper: its day-lane reservations are swept back to pass
///      credits. A window of that same day, seeded ahead of time by a vault window-ahead comp,
///      must not be armable afterwards — arming it would bind a table and pay FLIP off a day
///      that banked no ladder. `armBonusWindow` now refuses to arm any window whose day never ran
///      `openBonusDay` (its boost budget is zero). This suite proves that guard on both orderings
///      against the sweep, plus a positive control that an ordinary, opened day still arms and
///      settles.
contract CrapsLapsedDayArmTest is CrapsPins {
    LapseArmHarness internal craps;

    uint256 internal constant PLAIN_WORD = 40 << 8;
    uint256 internal constant GRANULE = 100e18;
    uint8 internal constant KIND_WINDOW_AHEAD = 5;
    uint256 internal constant ROUTINE_WINDOW_PRICE = 1_227 ether;
    uint256 internal constant OPENER_SEAT_VALUE = 2_433 ether;
    uint256 internal constant TAIL_WINDOW_PRICE = 14_235 ether;

    address internal alice = makeAddr("alice");
    address internal dave = makeAddr("dave");

    function setUp() public {
        _installPins();
        craps = new LapseArmHarness();
        vm.warp(block.timestamp + 1 days);
        _setIndex(4);
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
        uint256 floor_ = craps.SYBIL_SCORE_FLOOR();
        game.setScore(alice, floor_);
        game.setScore(dave, floor_);
        flip.setCompLane(100_000_000 ether);
    }

    function _code(uint8 kind, address to, bool high, uint24 arg, uint8 count) internal pure returns (uint256) {
        return uint256(uint160(to)) | (uint256(kind) << 160) | (high ? (1 << 168) : 0) | (uint256(arg) << 176)
            | (uint256(count) << 200);
    }

    function _slotAt(uint24 day, uint256 period) internal view returns (uint64) {
        return uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + period + 1);
    }

    function _countSig(Vm.Log[] memory logs, bytes32 sig) internal pure returns (uint256 n) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == sig) ++n;
        }
    }

    function _finalizedPot(Vm.Log[] memory logs) internal pure returns (uint256 pot, bool found) {
        bytes32 sig = keccak256("CrapsBattleFinalized(bytes32,uint8,uint64,uint256,uint256,uint256,uint256)");
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length != 2 || logs[i].topics[0] != sig) continue;
            (,,,,, pot) = abi.decode(logs[i].data, (uint8, uint64, uint256, uint256, uint256, uint256));
            found = true;
        }
    }

    function _passesCreditedTo(Vm.Log[] memory logs, address who) internal pure returns (uint256 n) {
        bytes32 sig = keccak256("CrapsPassesCredited(address,bool,uint256)");
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length != 2 || logs[i].topics[0] != sig) continue;
            if (address(uint160(uint256(logs[i].topics[1]))) != who) continue;
            (, uint256 count) = abi.decode(logs[i].data, (bool, uint256));
            n += count;
        }
    }

    /// @dev Day G = tomorrow. A day-lane reservation (alice, via a pass) and a vault window-ahead
    ///      comp (dave, period 1) both land on G before its word exists. G then stalls: the clock
    ///      lands on G+1, G's word is backfilled and only G+1 opens. The keeper sweeps G as
    ///      lapsed and refunds alice FIRST. The comped window of G is then refused arming: the
    ///      guard reads G's own boost budget, which is still zero, so no table is ever bound and
    ///      no FLIP is credited for it.
    function test_unopenedDayWindowCannotArm() public {
        uint24 today = craps.currentDayIndex();
        uint24 dayG = today + 1;
        uint64 slot = _slotAt(dayG, 1);
        uint64 daySlotG = uint64(uint256(dayG) * craps.BONUS_SLOTS_PER_DAY());

        // Alice's day-lane reservation on G, paid with a pass credit.
        vm.prank(ContractAddresses.GAME);
        craps.creditPasses(alice, 1, 0);
        vm.prank(alice);
        craps.applyCrapsPasses(dayG, 1, false);
        (uint256 aN,) = craps.passCreditsOf(alice);
        assertEq(aN, 0, "alice's pass was not spent on the reservation");
        assertEq(craps.dayTicketsOf(dayG), 1, "alice's day ticket was not written");

        // Dave's vault window-ahead comp on (G, period 1) seeds the window's field.
        vm.prank(ContractAddresses.VAULT);
        craps.vaultComp(_code(KIND_WINDOW_AHEAD, dave, false, dayG, 1) | (uint256(1) << 208));
        (uint256 reserved,) = craps.windowReservedOf(slot);
        assertEq(reserved, 1, "the comp did not seed the window field");

        // THE STALL: G never opens. The clock lands on G+1; the advance backfills G's word and
        // opens G+1 only (openBonusDay opens the wall day alone).
        vm.warp(vm.getBlockTimestamp() + 2 days);
        assertEq(craps.currentDayIndex(), dayG + 1, "the clock did not land on G+1");
        _setDailyWord(dayG, uint256(keccak256("gap-day-word")));
        _setDailyWord(dayG + 1, PLAIN_WORD);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        assertEq(craps.boostBudgetOf(dayG), 0, "the stalled day opened");
        assertTrue(craps.dailyWordAt(dayG) != 0, "the stalled day has no backfilled word");
        assertTrue(craps.boostBudgetOf(dayG + 1) != 0, "the wall day did not open");

        // THE SWEEP: the keeper crosses `today` (never opened, empty) and then G, refunding alice.
        uint256 laneBefore = flip.compLane();
        vm.recordLogs();
        for (uint256 i = 0; i < 8 && craps.keeperSlot() < daySlotG + 8; ++i) {
            craps.keepScheduled(type(uint64).max);
        }
        Vm.Log[] memory sweepLogs = vm.getRecordedLogs();
        assertGe(craps.keeperSlot(), daySlotG + 8, "the keeper did not cross G");
        assertEq(_countSig(sweepLogs, keccak256("CrapsDayLapsed(uint24,uint64)")), 2, "today and G did not both lapse");
        (aN,) = craps.passCreditsOf(alice);
        assertEq(aN, 1, "alice's lapsed reservation was not refunded as a pass");
        assertEq(craps.bonusCursorOf(daySlotG), 1, "the sweep cursor did not walk alice's seat");
        // Dave's comp is refunded to the comp lane at the price it was charged (a routine window).
        assertEq(flip.compLane() - laneBefore, ROUTINE_WINDOW_PRICE, "the lapsed comp seat was not refunded to the lane");
        assertEq(craps.bonusCursorOf(slot), 1, "the window cursor did not walk dave's seat");

        // The sweep left the window's field and dave's seat untouched.
        (uint256 entrantsBefore,) = craps.fieldOf(bytes32(uint256(slot)));
        assertEq(entrantsBefore, 1, "the sweep cleared the comped window field");
        assertEq(craps.slotIndexOf(slot), 0, "the window is already armed");

        // THE ARM on the lapsed day's comped window is now refused. It must not bind a table or
        // credit any FLIP for it.
        uint256 aliceStakeBefore = coinflip.staked(alice);
        uint256 daveStakeBefore = coinflip.staked(dave);
        vm.recordLogs();
        vm.expectRevert(CrapsBattle.BonusPeriodSpent.selector);
        craps.armBonusWindow(slot);
        Vm.Log[] memory armLogs = vm.getRecordedLogs();
        (, bool finalized) = _finalizedPot(armLogs);
        assertFalse(finalized, "the refused arm still finalized a pot");
        assertEq(craps.slotIndexOf(slot), 0, "the refused arm bound a table anyway");
        assertEq(coinflip.staked(alice), aliceStakeBefore, "alice was credited FLIP off a refused arm");
        assertEq(coinflip.staked(dave), daveStakeBefore, "dave was credited FLIP off a refused arm");
    }

    /// @dev The other order: try to arm the comped window FIRST, before the keeper ever sweeps
    ///      the day. The guard reads G's own boost budget rather than the sweep's cursor, so
    ///      arming first changes nothing — the arm is refused either way, and the keeper's sweep
    ///      afterwards still refunds the seat the refused arm never touched.
    function test_unopenedDayWindowCannotArmBeforeSweep() public {
        uint24 today = craps.currentDayIndex();
        uint24 dayG = today + 1;
        uint64 slot = _slotAt(dayG, 1);
        uint64 daySlotG = uint64(uint256(dayG) * craps.BONUS_SLOTS_PER_DAY());

        vm.prank(ContractAddresses.GAME);
        craps.creditPasses(alice, 1, 0);
        vm.prank(alice);
        craps.applyCrapsPasses(dayG, 1, false);
        vm.prank(ContractAddresses.VAULT);
        craps.vaultComp(_code(KIND_WINDOW_AHEAD, dave, false, dayG, 1) | (uint256(1) << 208));

        vm.warp(vm.getBlockTimestamp() + 2 days);
        _setDailyWord(dayG, uint256(keccak256("gap-day-word")));
        _setDailyWord(dayG + 1, PLAIN_WORD);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        assertEq(craps.boostBudgetOf(dayG), 0, "the stalled day opened");

        // THE ARM, attempted before the sweep even runs.
        vm.expectRevert(CrapsBattle.BonusPeriodSpent.selector);
        craps.armBonusWindow(slot);
        assertEq(craps.slotIndexOf(slot), 0, "the refused arm bound a table anyway");

        // Now the keeper sweeps G as lapsed and refunds the seat the refused arm never touched.
        for (uint256 i = 0; i < 8 && craps.keeperSlot() < daySlotG + 8; ++i) {
            craps.keepScheduled(type(uint64).max);
        }
        (uint256 aN,) = craps.passCreditsOf(alice);
        assertEq(aN, 1, "alice's reservation was not refunded as a pass");
    }

    /// @dev THE CONTROL: the guard must not stop an ordinary day. G here is opened normally, on
    ///      its own wall-day crank with its own word, no stall in between — the same day-lane
    ///      reservation and window-ahead comp still fold in, the window still arms, and it still
    ///      settles and pays out, exactly as before the fix.
    function test_openedDayWindowStillArms() public {
        uint24 today = craps.currentDayIndex();
        uint24 dayG = today + 1;
        uint64 slot = _slotAt(dayG, 1);

        // Alice's day-lane reservation on G, paid with a pass credit.
        vm.prank(ContractAddresses.GAME);
        craps.creditPasses(alice, 1, 0);
        vm.prank(alice);
        craps.applyCrapsPasses(dayG, 1, false);

        // Dave's vault window-ahead comp on (G, period 1) seeds the window's field.
        vm.prank(ContractAddresses.VAULT);
        craps.vaultComp(_code(KIND_WINDOW_AHEAD, dave, false, dayG, 1) | (uint256(1) << 208));

        // Land exactly on G and open it the normal way: `openBonusDay` runs while G is still the
        // wall day, off G's own word, with no stall in between.
        vm.warp(vm.getBlockTimestamp() + 1 days);
        assertEq(craps.currentDayIndex(), dayG, "the clock did not land on G");
        _setDailyWord(dayG, PLAIN_WORD);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        assertTrue(craps.boostBudgetOf(dayG) != 0, "G did not open normally");
        // Opening also seats the vault and sDGNRS. Arming must fold every day ticket,
        // including Alice's reservation, into Dave's one window-only seat.
        uint256 daySeats = craps.dayTicketsOf(dayG);
        assertEq(daySeats, 3, "Alice and the two protocol day seats must be present");

        // Move past G's own window close so the arm door is live for it.
        vm.warp(vm.getBlockTimestamp() + 1 days);

        uint48 index = craps.armBonusWindow(slot);
        assertTrue(craps.slotIndexOf(slot) != 0, "the opened day's window did not arm");
        (uint256 entrants,) = craps.fieldOf(bytes32(uint256(slot)));
        assertEq(entrants, daySeats + 1, "the arm must fold all day tickets into Dave's window seat");

        uint256 stakeUnits = craps.stakeUnitsOf(slot);
        uint256 bounties = stakeUnits * entrants * GRANULE;

        _setWord(index, uint256(keccak256("settling-word-control")));
        vm.recordLogs();
        craps.resolveSlot(slot, WHOLE_FIELD);
        Vm.Log[] memory settleLogs = vm.getRecordedLogs();

        assertEq(craps.bonusCursorOf(slot), entrants, "every seat must settle on the opened day's window");
        (uint256 pot, bool finalized) = _finalizedPot(settleLogs);
        assertTrue(finalized, "the opened day's window did not finalize");
        assertGt(pot, bounties, "no boost was paid on top of the bounties");
        assertTrue(coinflip.totalCredited() != 0, "nobody was paid at settlement");
    }

    /// @dev A coin draw's opener winner, seated by the GAME on tomorrow's opener, loses that seat
    ///      when tomorrow lapses. The sweep pays the winner the seat's price in FLIP (the opener's
    ///      expected cost, the same figure a comp of it is charged) and leaves the comp lane alone.
    function test_lapsedCoinDrawSeatPaysItsWinnerInFlip() public {
        uint24 dayG = craps.currentDayIndex() + 1;
        uint64 slot = _slotAt(dayG, 0);
        uint64 daySlotG = uint64(uint256(dayG) * craps.BONUS_SLOTS_PER_DAY());

        vm.prank(ContractAddresses.GAME);
        craps.vaultComp(_code(KIND_WINDOW_AHEAD, dave, false, dayG, 1));
        (uint256 reserved,) = craps.windowReservedOf(slot);
        assertEq(reserved, 1, "the coin draw did not seat its winner");

        _lapse(dayG);
        uint256 laneBefore = flip.compLane();
        uint256 daveBefore = coinflip.staked(dave);
        for (uint256 i = 0; i < 8 && craps.keeperSlot() < daySlotG + 8; ++i) {
            craps.keepScheduled(type(uint64).max);
        }
        assertGe(craps.keeperSlot(), daySlotG + 8, "the keeper did not cross G");
        assertEq(coinflip.staked(dave) - daveBefore, OPENER_SEAT_VALUE, "the winner was not paid the seat's value");
        assertEq(flip.compLane(), laneBefore, "a coin-draw seat was refunded to the comp lane");
        assertEq(craps.bonusCursorOf(slot), 1, "the window cursor did not walk the seat");
    }

    /// @dev The window refunds are metered like the day seats: a budget of one seat per call walks
    ///      a lapsed day's reservations across several calls, each reporting progress, and never
    ///      refunds a seat twice.
    function test_lapsedWindowRefundsResumeAcrossCalls() public {
        uint24 dayG = craps.currentDayIndex() + 1;
        uint64 daySlotG = uint64(uint256(dayG) * craps.BONUS_SLOTS_PER_DAY());
        address erin = makeAddr("erin");
        vm.startPrank(ContractAddresses.VAULT);
        craps.vaultComp(_code(KIND_WINDOW_AHEAD, dave, false, dayG, 1) | (uint256(1) << 208));
        craps.vaultComp(_code(KIND_WINDOW_AHEAD, erin, true, dayG, 1) | (uint256(6) << 208));
        vm.stopPrank();

        _lapse(dayG);
        // Cross the empty lapsed `today` first with an unmetered call.
        while (craps.keeperSlot() < daySlotG) craps.keepScheduled(type(uint64).max);
        uint256 laneBefore = flip.compLane();
        uint256 calls;
        while (craps.keeperSlot() < daySlotG + 8) {
            (bool progressed,) = craps.keepScheduled(8);
            assertTrue(progressed, "a metered sweep call reported no progress");
            ++calls;
            require(calls < 10, "the sweep did not finish");
        }
        assertEq(calls, 2, "two seats at one per call; the call that finishes the day crosses it");
        assertEq(
            flip.compLane() - laneBefore,
            ROUTINE_WINDOW_PRICE + TAIL_WINDOW_PRICE * 19,
            "each comp refunded exactly once at its own price"
        );
    }

    /// @dev Make `day` (tomorrow) lapse: the clock lands on the day after, `day` gets a backfilled
    ///      word, and only the wall day opens.
    function _lapse(uint24 day) internal {
        vm.warp(vm.getBlockTimestamp() + 2 days);
        _setDailyWord(day, uint256(keccak256("gap-day-word")));
        _setDailyWord(day + 1, PLAIN_WORD);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        assertEq(craps.boostBudgetOf(day), 0, "harness: the stalled day opened");
    }
}
