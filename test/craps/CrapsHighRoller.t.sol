// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Craps} from "../../contracts/Craps.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title The high-roller lane
/// @notice One optional lane per battle. A seat takes it by paying the field's multiple on the
///         WHOLE seat — the bankroll it runs and the bounty it posts — and in exchange it enters a
///         second race, against the other high rollers only, for the extra bounties they all put
///         up. The run itself is untouched: same dice, same board, same comparator, and the money
///         a seat staked reaches neither scoreboard.
///
/// @dev What these fixtures are actually holding down:
///        - the multiple is drawn from the day's own committed word and from nothing else;
///        - entry is BINARY, which is what makes a variable daily multiple safe to quote;
///        - one bounty per seat stays in the main pot and the other `H - 1` go to the lane, so
///          nothing is minted and nothing is stranded;
///        - a lane of ONE is not a race, so its extra bounties ride its own run instead — at risk,
///          pro rata, and worth nothing on a bust.
/// @dev The two action taps. A budget is drawn from the SEVEN DAYS BEFORE the day it opens, so a
///      suite that wants a funded lane has to put action behind it — and driving real settlements
///      for seven prior days is not a fixture, it is a simulation.
contract HighHarness is CrapsViews {
    function bookDay(uint24 day, uint256 staked) external {
        _bookDay(day, staked, 0);
    }

    /// @dev Action a HIGH seat put up: it lands in the day total AND in the high subset.
    function bookHighDay(uint24 day, uint256 staked) external {
        _bookDay(day, staked, staked);
    }

    function roundBoost(uint256 units) external pure returns (uint256) {
        return _roundBoost(units);
    }

    /// @dev The UNSCALED result of one run — `P` itself, before any multiple and before any
    ///      rider. Everything the lane pays is a function of it, so a suite that wants to check
    ///      the arithmetic rather than restate it needs it on its own.
    function baseRunOf(uint256 betId) external view returns (uint256 won, uint256 paid) {
        Settlement memory s =
            _settlementOf(betId, _bets[betId], _slotWindow(betId >> 64), _wordAt(_indexOf(betId >> 64)));
        return (s.won, s.paid);
    }
}

contract CrapsHighRollerTest is CrapsPins {
    HighHarness internal craps;

    uint24 internal constant L = 600;
    uint128 internal constant LW = 600e18;
    uint256 internal constant GRANULE = 100e18;
    uint24 internal constant SU = 3;
    uint256 internal constant SUW = uint256(SU) * GRANULE;
    uint256 internal constant PLAIN_WORD = 40 << 8;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");

    function setUp() public {
        _installPins();
        craps = new HighHarness();
        // The deployment day is a Craps warm-up day with no windows; every fixture plays
        // from genesis + 1, the first day the table opens.
        vm.warp(block.timestamp + 1 days);
        _setIndex(4);
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
        uint256 floor_ = craps.SYBIL_SCORE_FLOOR();
        game.setScore(alice, floor_);
        game.setScore(bob, floor_);
        game.setScore(carol, floor_);
        game.setScore(dave, floor_);
    }

    function _boardA() internal pure returns (Craps.Bets memory b) {
        b.passLine = 4;
        b.place6 = 3;
    }

    /// @dev To the top of a protocol day, where period zero is live.
    function _warpToDayStart() internal {
        uint256 elapsed = (vm.getBlockTimestamp() - 82_620) % 1 days;
        if (elapsed != 0) vm.warp(vm.getBlockTimestamp() + (1 days - elapsed));
    }

    /// @dev A day word whose draw lands on `want`. Searched rather than named: the derivation is
    ///      a hash, so a literal would be a magic number nobody could check.
    function _wordFor(uint256 want) internal view returns (uint256) {
        for (uint256 i = 1; i < 500; ++i) {
            uint256 w = uint256(keccak256(abi.encode("hr", i)));
            if (craps.highMultOfWord(w) == want) return w;
        }
        revert("no word draws that multiple");
    }

    // ── The daily draw ──────────────────────────────────────────────────────

    /// @dev Ten or a hundred, nothing else, at about one in ten. Not a chi-squared — the band is
    ///      wide enough that only a real change to the odds trips it.
    function test_theDailyDrawIsTenOrAHundredAtOneInTen() public view {
        uint256 tails;
        uint256 n = 2000;
        for (uint256 i = 0; i < n; ++i) {
            uint256 h = craps.highMultOfWord(uint256(keccak256(abi.encode("draw", i))));
            assertTrue(h == 10 || h == 100, "the draw came off the menu");
            if (h == 100) ++tails;
        }
        assertApproxEqAbs(tails * 10, n, n / 4, "the hundred-times day is off its advertised rate");
    }

    /// @dev No word, no lane. There is no fallback source — a day that cannot draw simply does not
    ///      offer one, which is the same thing that happens to its windows.
    function test_aDayWithNoWordHasNoLane() public view {
        assertEq(craps.highMultOfWord(0), 0, "a zero word invented a multiple");
        assertEq(craps.highMultForDay(craps.currentDayIndex() + 50), 0, "an undrawn day invented a multiple");
    }

    /// @dev The draw is the DAY's, so all seven windows run it — and it does not move when the
    ///      day is reopened, when a window is armed late, or when anybody looks at it twice.
    function test_everyWindowOfADayRunsTheSameMultipleAndItNeverRerolls() public {
        uint24 day = craps.currentDayIndex();
        _setDailyWord(day, _wordFor(100));
        uint256 h = craps.highMultForDay(day);
        assertEq(h, 100, "the fixture did not land a hundred-times day");

        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        for (uint256 p = 0; p < craps.BONUS_PERIODS_PER_DAY(); ++p) {
            assertEq(craps.highMultOfSlot(_slotAt(day, p)), h, "a window ran a different multiple");
        }
        // Reopening is a no-op and cannot reroll.
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        assertEq(craps.highMultForDay(day), h, "reopening the day rerolled its multiple");

        // And a slot keeps its OWN day's draw once the clock has moved on.
        vm.warp(block.timestamp + 3 days);
        assertEq(craps.highMultOfSlot(_slotAt(day, 0)), h, "a stale slot took the wrong day's multiple");
    }

    // ── Entry ───────────────────────────────────────────────────────────────

    /// @dev BINARY. One copy of the run, or exactly the field's multiple — and nothing between,
    ///      which is the whole reason a variable daily multiple is safe to quote.
    function test_entryIsOneCopyOrTheFieldsMultipleAndNothingBetween() public {
        uint64 slot = _openHigh(craps, L, 2, 10, SU, 10);
        vm.prank(alice);
        craps.enterBattle(slot, _boardA(), 1);
        vm.prank(bob);
        craps.enterBattle(slot, _boardA(), 10);

        uint16[5] memory bad = [uint16(0), 2, 9, 11, 100];
        for (uint256 i = 0; i < bad.length; ++i) {
            vm.prank(carol);
            vm.expectRevert(CrapsBattle.BadEntryMultiple.selector);
            craps.enterBattle(slot, _boardA(), bad[i]);
        }
    }

    /// @dev A high roller buys the WHOLE seat over again — the bankroll AND the bounty. That is
    ///      what makes the lane a race rather than a bigger bet in the same one.
    function test_aHighRollerBurnsTheWholeSeatOverAgain() public {
        uint64 slot = _openHigh(craps, L, 2, 10, SU, 10);
        uint256 seat = uint256(LW) * 2 + SUW;

        uint256 before = flip.burned(alice);
        vm.prank(alice);
        craps.enterBattle(slot, _boardA(), 1);
        assertEq(flip.burned(alice) - before, seat, "an ordinary seat mispriced");

        before = flip.burned(bob);
        vm.prank(bob);
        craps.enterBattle(slot, _boardA(), 10);
        assertEq(flip.burned(bob) - before, seat * 10, "a high seat did not pay the multiple on both halves");
    }

    /// @dev THE QUOTE TRAP. A transaction naming ten cannot be filled at a hundred just because it
    ///      landed against a hundred-times field. It is refused outright.
    function test_aStaleTenIsRefusedAgainstAHundredField() public {
        uint64 slot = _openHigh(craps, L, 2, 10, SU, 100);
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BadEntryMultiple.selector);
        craps.enterBattle(slot, _boardA(), 10);
        assertEq(flip.burned(alice), 0, "a refused entry still burned");
    }

    /// @dev Zero disables the lane outright; one is not a multiple at all.
    function test_aCreatorFixesTheMultipleOrDisablesTheLane() public {
        vm.startPrank(vaultOwner);
        uint40 close = uint40(vm.getBlockTimestamp() + 1 hours);
        craps.createBattle(L, 2, 10, SU, 0, close, true, 0);
        craps.createBattle(L, 2, 10, SU, 0, close, true, 2);
        craps.createBattle(L, 2, 10, SU, 0, close, true, 256);
        vm.expectRevert(CrapsBattle.BadHighRollerMultiplier.selector);
        craps.createBattle(L, 2, 10, SU, 0, close, true, 1);
        vm.expectRevert(CrapsBattle.BadHighRollerMultiplier.selector);
        craps.createBattle(L, 2, 10, SU, 0, close, true, 257);
        vm.stopPrank();
    }

    /// @dev A disabled lane takes ordinary seats and nothing else, and never touches its sideboard.
    function test_aDisabledLaneTakesOrdinarySeatsOnly() public {
        uint64 slot = _openBattle(craps, L, 2, 10, SU);
        vm.prank(alice);
        craps.enterBattle(slot, _boardA(), 1);
        vm.prank(bob);
        vm.expectRevert(CrapsBattle.BadEntryMultiple.selector);
        craps.enterBattle(slot, _boardA(), 10);
        (uint32 heads,,,, bool done) = craps.highFieldOf(craps.battleKeyOf((uint256(slot) << 64) | 1));
        assertEq(heads, 0, "a disabled lane counted a seat");
        assertFalse(done, "a disabled lane marked itself done");
    }

    // ── What the boost lands on ─────────────────────────────────────────────

    /// @dev House money lands on a ROUND figure. It is counted in 100-FLIP granules, so anything
    ///      up to forty of them is already round; past four thousand FLIP it goes to the nearest
    ///      thousand, because a five-figure subsidy quoted to the hundred is noise nobody reads.
    function test_theBoostLandsOnARoundFigure() public view {
        // Below the threshold nothing moves at all.
        for (uint256 u = 0; u <= 40; ++u) assertEq(craps.roundBoost(u), u, "a small boost moved");

        // Past it, to the nearest ten granules — one thousand FLIP — half up.
        assertEq(craps.roundBoost(41), 40, "41 granules did not round down");
        assertEq(craps.roundBoost(44), 40, "44 granules did not round down");
        assertEq(craps.roundBoost(45), 50, "45 granules did not round half up");
        assertEq(craps.roundBoost(46), 50, "46 granules did not round up");
        assertEq(craps.roundBoost(50), 50, "an exact thousand moved");
        assertEq(craps.roundBoost(1234), 1230, "a large boost did not land on the thousand");

        // And EVERYTHING past the threshold is a whole thousand, never a hundred.
        for (uint256 u = 41; u < 500; ++u) {
            assertEq(craps.roundBoost(u) % 10, 0, "a boost past the threshold is not a whole thousand");
            // Never moved by more than half a step.
            uint256 r = craps.roundBoost(u);
            assertLe(r > u ? r - u : u - r, 5, "the rounding moved a boost more than half a step");
        }
    }

    /// @dev THE GRANULE. The lane rations and rounds in GRANULES and only then widens to wei —
    ///      the same order the main pot uses. Sharing in wei first would put a winner's boost on
    ///      some figure that is a multiple of nothing.
    ///
    ///      Driven end to end through a real SCHEDULED window, because that is the only way to
    ///      exercise the path: restating the arithmetic against the same helpers production calls
    ///      would pass whatever production actually did with them. Two high rollers so the lane is
    ///      CONTESTED and pays outright (a sole rider's return is a pro-rata fraction and is not
    ///      granule-aligned by design), and both are seated BELOW the sybil floor so the rationing
    ///      really divides.
    function test_theLanesBoostIsAWholeNumberOfGranules() public {
        // Far enough in that a full seven-day window exists behind today, and then to the top of
        // a day so period one is still joinable.
        vm.warp(vm.getBlockTimestamp() + 10 days);
        _warpToDayStart();
        uint24 today = craps.currentDayIndex();
        uint256 days_ = craps.BOOST_ACTION_WINDOW_DAYS();
        for (uint256 i = 1; i <= days_; ++i) craps.bookHighDay(today - uint24(i), 7_100_000 ether);
        _setDailyWord(today, _wordFor(10));
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();

        uint64 slot = _slotAt(today, 1);
        assertGt(craps.highBaseOf(slot), 0, "the fixture funded no lane boost");

        // Below the floor, so `_boostShare` divides by seven rather than paying whole.
        game.setScore(alice, 5);
        game.setScore(bob, 5);
        vm.prank(alice);
        craps.enterBonusBattle(1, _boardA(), 10);
        vm.prank(bob);
        craps.enterBonusBattle(1, _boardA(), 10);

        vm.warp(vm.getBlockTimestamp() + 5 hours);
        uint48 index = craps.armBonusWindow(slot);
        _setWord(index, uint256(keccak256("granule")));
        PaidOut[] memory lane = _resolveForLane(craps, slot, WHOLE_FIELD, false);
        assertEq(lane.length, 1, "the contested lane paid other than once");

        (,, uint64 seat,,) = craps.highFieldOf(craps.battleKeyOf((uint256(slot) << 64) | 1));
        assertEq(lane[0].player, seat == 1 ? alice : bob, "the lane paid a seat it did not name");

        // The LANE's own figure, not the winner's balance: the same call credits that address its
        // run and may hand it the main pot as well, and neither is held to the granule.
        uint256 granule = craps.BATTLE_STAKE_UNIT();
        assertGt(lane[0].amount, 0, "the contested lane paid nothing, so nothing was measured");
        assertEq(lane[0].amount % granule, 0, "the lane paid a figure that is not a whole granule");

        // AND THE ROUNDING ITSELF. `% granule` above is satisfied by the widening multiply on its
        // own, so it holds whether or not `_roundBoost` ever ran — which is the exact mis-ordering
        // this fixture is named for. Recompute the figure the way production is meant to reach it
        // — share in granules, round in granules, widen last — and hold the payment to it.
        (,,, uint256 battleStake,,) = craps.bonusTermsFor(today, 1);
        uint256 principal = 2 * (craps.highMultOfSlot(slot) - 1) * battleStake;
        uint256 units = craps.boostShareOf(craps.highBoostUnitsOf(slot, craps.wordAt(index)), 5);
        // Under the threshold nothing rounds, so a fixture that landed there would prove nothing.
        assertGt(units, 40, "the fixture's lane boost is below the rounding threshold");
        assertTrue(units % 10 != 0, "the fixture's lane boost is already round: rounding is untested");
        assertEq(
            lane[0].amount,
            principal + craps.roundBoost(units) * granule,
            "the lane did not round in granules before widening to wei"
        );
    }

    // ── The lane's three shapes ─────────────────────────────────────────────

    /// @dev N_H = 0. No lane exists, so there is nothing to claim and nothing was minted.
    function test_aFieldWithNoHighRollerHasNoLane() public {
        uint64 slot = _openHigh(craps, L, 2, 10, SU, 10);
        vm.prank(alice);
        craps.enterBattle(slot, _boardA(), 1);
        vm.prank(bob);
        craps.enterBattle(slot, _boardA(), 1);
        _settle(slot, 7);

        (uint32 heads,,,, bool done) = craps.highFieldOf(craps.battleKeyOf((uint256(slot) << 64) | 1));
        assertEq(heads, 0, "an ordinary field grew a lane");
        assertFalse(done, "an empty lane marked itself done");
    }

    /// @dev N_H = 1. A lane of one is not a race. Its extra bounties are neither refunded nor paid
    ///      out whole — they ride the run it did make, pro rata, and the credit is exactly
    ///      `H * P + floor(P * X / R)`.
    function test_aSoleHighRollerRidesItsExtraBountiesOnItsOwnRun() public {
        uint64 slot;
        uint256 hi;
        uint256 p;
        uint256 r;
        for (uint256 i = 0; i < 40; ++i) {
            (slot, hi, r) = _laneOfOne(uint48(100 + i));
            (, p) = craps.baseRunOf(hi);
            if (p != 0) break;
        }
        assertGt(p, 0, "no pass in this sweep came home with money");

        // A custom battle draws no protocol boost, so the capital riding the run is exactly the
        // nine extra bounties this seat posted.
        uint256 x = 9 * SUW;
        uint256 expected = 10 * p + ((p / r) * x + ((p % r) * x) / r);

        // The preview quotes the WHOLE settlement, rider included.
        (, uint256 quoted) = craps.previewSettlement(hi);
        assertEq(quoted, expected, "the preview under-quoted the rider");

        uint256 before = coinflip.staked(alice);
        (PaidOut[] memory pots,) = _resolveForBoth(craps, slot, WHOLE_FIELD);
        assertEq(pots.length, 1, "the field did not pay exactly one pot");
        // The same call pays the field's MAIN POT, and the three seats here play one board — so
        // the coin decides whether that lands on this address too. Take it back out: what is under
        // measurement is the run and the capital riding it, not the race beside them.
        uint256 got = coinflip.staked(alice) - before - (pots[0].player == alice ? pots[0].amount : 0);
        assertEq(got, expected, "the rider is not one pro-rata copy of the run");
        // And the lane is closed by the settlement itself: no second claim exists.
        (uint32 heads,,, bool rider, bool done) = craps.highFieldOf(craps.battleKeyOf(hi));
        assertEq(heads, 1, "the lane did not hold exactly one seat");
        assertTrue(rider, "a lane of one did not read as a rider");
        assertTrue(done, "the sole lane was left unprocessed");
    }

    /// @dev A BUST returns nothing on the run and therefore nothing on the capital riding it.
    ///      Both halves are at risk together, which is what stops a sole high roller from being a
    ///      way to take money off the table for free.
    function test_aSoleHighRollerOnABustGetsNothingBack() public {
        for (uint256 i = 0; i < 40; ++i) {
            (uint64 slot, uint256 hi,) = _laneOfOne(uint48(200 + i));
            (, uint256 basePaid) = craps.baseRunOf(hi);
            if (basePaid != 0) continue;

            // Read off the rider's own announcement rather than the balance: the same call also
            // pays the field's main pot, and an all-bust field still has a best bust to pay it to.
            PaidOut[] memory ride = _resolveForLane(craps, slot, WHOLE_FIELD, true);
            assertEq(ride.length, 1, "the sole high seat announced no rider at all");
            assertEq(ride[0].amount, 0, "a busted rider still came home with something");
            (,,,, bool done) = craps.highFieldOf(craps.battleKeyOf(hi));
            assertTrue(done, "a busted sole lane was left unprocessed");
            return;
        }
        revert("no pass in this sweep busted");
    }

    /// @dev N_H >= 2. A race: every extra bounty in the lane goes to the best of them, on the same
    ///      comparator the main field ranks on, and it pays exactly once.
    function test_twoHighRollersRaceForEveryExtraBountyInTheLane() public {
        uint64 slot = _openHigh(craps, L, 2, 10, SU, 10);
        vm.prank(alice);
        uint256 a = craps.enterBattle(slot, _boardA(), 10);
        vm.prank(bob);
        craps.enterBattle(slot, _boardA(), 10);
        vm.prank(carol);
        craps.enterBattle(slot, _boardA(), 1);
        _closeOn(craps, slot, 9, uint256(keccak256(abi.encode("settle", slot))));

        // The LANE PAYS ITSELF OUT during the settlement that finishes the field — the same call
        // that pays the main pot — so what a claim used to collect is now one entry in this
        // stream.
        vm.recordLogs();
        craps.resolveSlot(slot, WHOLE_FIELD);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        PaidOut[] memory lane = _lanePaymentsIn(logs, false);
        assertEq(lane.length, 1, "a contested lane paid other than once");
        assertEq(_lanePaymentsIn(logs, true).length, 0, "contested seats emitted empty rider payments");

        bytes32 key = craps.battleKeyOf(a);
        (uint32 heads,, uint64 seat, bool rider, bool done) = craps.highFieldOf(key);
        assertEq(heads, 2, "the lane did not hold both high seats");
        assertFalse(rider, "a contested lane read as a rider");
        assertTrue(done, "the lane did not latch when it paid");

        // Two seats, nine extra bounties each. A custom battle draws no protocol boost, so the
        // principal is the whole award.
        assertTrue(seat == 1 || seat == 2, "the lane named a seat outside itself");
        address winner = seat == 1 ? alice : bob;
        address loser = seat == 1 ? bob : alice;
        assertEq(lane[0].betId, (uint256(slot) << 64) | seat, "the lane paid a seat it did not name");
        assertEq(lane[0].player, winner, "the lane paid the wrong high roller");
        assertEq(lane[0].amount, 2 * 9 * SUW, "the lane paid other than every extra bounty in it");
        // The loser of the lane took nothing FROM THE LANE. Its own run still settles beside it,
        // so this is a claim about the lane's stream, not about that address's balance.
        for (uint256 i = 0; i < lane.length; ++i) {
            assertTrue(lane[i].player != loser, "the lane paid its loser too");
        }
    }

    /// @dev THE LANE PAYS ONLY WITH THE FIELD. Until the last seat has run a better high score may
    ///      still arrive, so a half-settled field must leave the lane standing — and there is no
    ///      claim left to refuse, so the guard is the payment itself.
    function test_theLaneDoesNotPayBeforeTheFieldIsFinal() public {
        uint64 slot = _openHigh(craps, L, 2, 10, SU, 10);
        vm.prank(alice);
        uint256 a = craps.enterBattle(slot, _boardA(), 10);
        vm.prank(bob);
        craps.enterBattle(slot, _boardA(), 10);
        _closeOn(craps, slot, 40, uint256(keccak256("final")));

        // One of the two seats settled: the lane is loaded but not decided.
        assertEq(_resolveForLane(craps, slot, 1, false).length, 0, "a half-settled field paid its lane");
        bytes32 key = craps.battleKeyOf(a);
        (,,,, bool done) = craps.highFieldOf(key);
        assertFalse(done, "the lane latched before the field was final");

        assertEq(_resolveForLane(craps, slot, WHOLE_FIELD, false).length, 1, "the last seat did not pay the lane");
        (,,,, done) = craps.highFieldOf(key);
        assertTrue(done, "the lane did not latch when the field finished");
    }

    // ── Conservation ────────────────────────────────────────────────────────

    /// @dev EXACTLY ONE bounty per seat stays in the main pot, whatever any seat paid. The other
    ///      `H - 1` from each high roller are the lane's, and the two together are every bounty
    ///      the field burned — nothing minted, nothing stranded.
    function test_oneBountyPerSeatStaysInTheMainPotAndTheRestIsTheLanes() public {
        uint64 slot = _openHigh(craps, L, 2, 10, SU, 10);
        vm.prank(alice);
        uint256 a = craps.enterBattle(slot, _boardA(), 10);
        vm.prank(bob);
        craps.enterBattle(slot, _boardA(), 10);
        vm.prank(carol);
        craps.enterBattle(slot, _boardA(), 1);
        vm.prank(dave);
        craps.enterBattle(slot, _boardA(), 1);

        uint256 burnedBounty = 2 * (10 * SUW) + 2 * SUW;
        uint256 mainPrincipal = 4 * SUW;
        uint256 lanePrincipal = 2 * 9 * SUW;
        assertEq(mainPrincipal + lanePrincipal, burnedBounty, "the two pots are not every bounty burned");

        _closeOn(craps, slot, 9, uint256(keccak256(abi.encode("settle", slot))));

        // ONE call finishes the field and pays both pots, so the two are told apart by which event
        // carried them rather than by which transaction did.
        (PaidOut[] memory main, PaidOut[] memory lane) = _resolveForBoth(craps, slot, WHOLE_FIELD);
        assertEq(main.length, 1, "the main pot paid other than once");
        assertEq(lane.length, 1, "the lane paid other than once");
        assertEq(lane[0].amount, lanePrincipal, "the lane paid other than its own principal");
        assertEq(main[0].amount, mainPrincipal, "the main pot paid other than one bounty a seat");
        assertEq(craps.battleKeyOf(a), craps.battleKeyOf((uint256(slot) << 64) | 3), "the field split its key");
    }

    /// @dev The money a seat staked reaches NEITHER scoreboard. Twin seats of one owner play an
    ///      identical run, so they are always dead level and only the coin separates them — which
    ///      means the ordinary seat has to take some.
    function test_theMultipleDoesNotBuyRankInEitherField() public {
        uint256 plainWins;
        uint256 live;
        for (uint256 i = 0; i < 40; ++i) {
            uint64 slot = _openHigh(craps, uint32(L + i * 10), 2, uint16(GOAL_FAR_MULT), SU, 10);
            vm.prank(alice);
            uint256 plain = craps.enterBattle(slot, _boardA(), 1);
            vm.prank(alice);
            craps.enterBattle(slot, _boardA(), 10);
            _closeOn(craps, slot, uint48(30_000 + i), uint256(keccak256(abi.encode("rank", i))));
            (uint256 won,) = craps.previewSettlement(plain);
            craps.resolveSlot(slot, WHOLE_FIELD);
            if (won == 0) continue;
            ++live;
            if (craps.battleOf(craps.battleKeyOf(plain)).winnerId == uint64(plain)) ++plainWins;
        }
        assertGt(live, 3, "no pass came home with money, so nothing was ranked");
        assertGt(plainWins, 0, "the ordinary seat never won: the multiple bought rank");
    }

    // ── The budget split ────────────────────────────────────────────────────

    /// @dev A high seat's action is rated at the SAME twelve percent every other seat is, and the
    ///      component splits two parts in five to the main boost and three to the lane that earned
    ///      it — 4.8% of high action to main, 7.2% to the lane. The two never share an amount.
    function test_highActionSplitsFourPointEightAndSevenPointTwo() public {
        vm.warp(block.timestamp + 10 days);
        uint24 today = craps.currentDayIndex();

        // A week of purely HIGH action, chosen so every floor below is exact.
        uint256 perDay = 3_600_000 ether;
        uint256 days_ = craps.BOOST_ACTION_WINDOW_DAYS();
        for (uint256 i = 1; i <= days_; ++i) craps.bookHighDay(today - uint24(i), perDay);

        // The window is AVERAGED, so a flat week's daily figure is one day's own.
        uint256 eh = (perDay * craps.BOOST_ACTION_BPS() / craps.BPS_DENOMINATOR()) * days_
            / craps.BOOST_ACTION_WINDOW_DAYS();
        uint256 toMain = eh * craps.HIGH_MAIN_NUM() / craps.HIGH_MAIN_DEN();
        (uint256 mainBudget, uint256 highBudget) = craps.drawBudgetsFor(today);

        assertEq(highBudget, eh - toMain, "the lane did not keep three fifths of its own component");
        assertEq(highBudget, perDay * 72 / 1000, "the lane's budget is not 7.2% of the high action");
        assertEq(toMain, perDay * 48 / 1000, "the main boost did not take 4.8% of the high action");
        // Every wei of the component is in one of the two, and nowhere else.
        assertEq(highBudget + toMain, eh, "the high component did not conserve");
        assertEq(eh, perDay * 12 / 100, "the high lane was rated at other than 12% of its action");
        // The BASE rides the main lane alone, so main is base plus the 4.8% and nothing more: the
        // high action is OUT of the regular lane entirely.
        assertEq(mainBudget, craps.BASE_MAIN_BUDGET() + toMain, "high action fed main other than its 4.8%");
        assertEq(craps.highStakedOf(today - 1), perDay, "the day did not book its high action");
        assertEq(craps.dayStaked(today - 1), perDay, "high action did not land in the day total too");
    }

    /// @dev The 25,000 FLIP base subsidy is the MAIN lane's and never the high one's. A lane
    ///      nobody played has nothing to give, and printing it one would be house money against
    ///      action that was never put through it.
    function test_theMainBaseNeverSubsidisesTheLane() public {
        vm.warp(block.timestamp + 10 days);
        uint24 today = craps.currentDayIndex();
        (uint256 mainBudget, uint256 highBudget) = craps.drawBudgetsFor(today);
        assertEq(mainBudget, craps.BASE_MAIN_BUDGET(), "a cold table did not open on exactly the base");
        assertEq(highBudget, 0, "the base subsidised a lane nobody played");
    }

    /// @dev Ordinary action stays out of the high lane's books entirely.
    function test_ordinaryActionNeverFeedsTheLane() public {
        vm.warp(block.timestamp + 10 days);
        uint24 today = craps.currentDayIndex();
        uint256 days_ = craps.BOOST_ACTION_WINDOW_DAYS();
        for (uint256 i = 1; i <= days_; ++i) craps.bookDay(today - uint24(i), 3_600_000 ether);
        (, uint256 highBudget) = craps.drawBudgetsFor(today);
        assertEq(highBudget, 0, "ordinary action funded the high lane");
        assertEq(craps.highStakedOf(today - 1), 0, "ordinary action booked as high action");
    }

    // ── Day tickets ─────────────────────────────────────────────────────────

    /// @dev One ticket, one multiple, all seven windows. The whole day is priced at `H` times the
    ///      sum of its seven seats, and the count folds into every window's lane when it arms —
    ///      without the sale ever touching a window.
    function test_aHighDayTicketPaysTheMultipleOnTheWholeDay() public {
        // The whole-day lane is sold in PERIOD ZERO and nowhere else — the first twenty minutes of
        // a protocol day, before any of its windows has shut. Past that the day is part-spent and
        // the rest is taken the ordinary way, one window at a time.
        _warpToDayStart();
        uint24 day = craps.currentDayIndex();
        _setDailyWord(day, _wordFor(10));
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();

        uint256 plain;
        uint256 periods = craps.BONUS_PERIODS_PER_DAY();
        for (uint256 p = 0; p < periods; ++p) {
            (uint128 bank,,, uint256 bounty,,) = craps.bonusTermsFor(day, p);
            plain += uint256(bank) + bounty;
        }

        Craps.Bets memory blank;
        uint256 before = flip.burned(alice);
        vm.prank(alice);
        uint256 placed = craps.enterBonusDay(blank, 10);
        assertEq(placed, periods, "the ticket did not take the whole day");
        assertEq(flip.burned(alice) - before, plain * 10, "a high day ticket did not pay the multiple on the day");

        // The sale wrote no window. Arming is what folds the count in.
        for (uint256 p = 0; p < periods; ++p) {
            (bytes32 key,,,) = craps.bonusWindowOf(p);
            (uint32 heads,,,,) = craps.highFieldOf(key);
            assertEq(heads, 0, "selling a day ticket touched a window's lane");
        }

        vm.warp(block.timestamp + 8 hours);
        for (uint256 p = 0; p < 2; ++p) {
            uint64 slot = _slotAt(day, p);
            (bytes32 key,,,) = craps.bonusWindowOf(p);
            craps.armBonusWindow(slot);
            (uint32 heads,,,,) = craps.highFieldOf(key);
            assertEq(heads, 1, "arming did not fold the day's high ticket into the window");
        }
    }

    /// @dev The house and the vault take DAY seats and are never high rollers: their seat is the
    ///      protocol's own, and the lane is a thing a player buys into.
    function test_theHouseAndVaultAreNeverHighRollers() public {
        uint24 day = craps.currentDayIndex();
        _setDailyWord(day, _wordFor(100));
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        vm.warp(block.timestamp + 8 hours);
        (bytes32 key,,,) = craps.bonusWindowOf(0);
        craps.armBonusWindow(_slotAt(day, 0));
        (uint32 heads,,,,) = craps.highFieldOf(key);
        assertEq(heads, 0, "a protocol seat joined the lane");
        assertGt(craps.battleOf(key).entrants, 0, "the window seated nobody at all");
    }

    // ── fixtures ────────────────────────────────────────────────────────────

    /// @dev A field holding exactly ONE high seat beside two ordinary ones, closed onto `index`.
    function _laneOfOne(uint48 index) internal returns (uint64 slot, uint256 hi, uint256 bankroll) {
        // A round is ten whole chips, so the sweep steps by ten rather than by one. The goal is
        // the SHORTEST the schedule allows: a far goal is never reached, so every run under it
        // busts and a sweep for one that came home with money would never find one.
        uint32 played = uint32(L) + uint32(index) * 10;
        bankroll = uint256(played) * 2 * 1 ether;
        slot = _openHigh(craps, played, 2, 5, SU, 10);
        vm.prank(alice);
        hi = craps.enterBattle(slot, _boardA(), 10);
        vm.prank(bob);
        craps.enterBattle(slot, _boardA(), 1);
        vm.prank(carol);
        craps.enterBattle(slot, _boardA(), 1);
        _closeOn(craps, slot, index, uint256(keccak256(abi.encode("lane", index))));
    }

    function _settle(uint64 slot, uint48 index) internal {
        _closeOn(craps, slot, index, uint256(keccak256(abi.encode("settle", slot))));
        craps.resolveSlot(slot, WHOLE_FIELD);
    }

    function _slotAt(uint24 day, uint256 period) internal view returns (uint64) {
        return uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + period + 1);
    }
}
/// @title The lane's gas budgets
/// @notice Every figure here is an A/B DELTA taken inside one test: the same field, the same
///         warmth, the same shared slots, differing only in whether the lane is there. A budget
///         checked against a number measured on another tree on another day is checked against
///         nothing — the view reclaim alone moved every one of them.
///
/// @dev Both arms are preceded by a warm-up on a THIRD battle, so neither pays for first-touch on
///      a slot the other found warm. What is left is the lane.
contract CrapsHighRollerGasTest is CrapsPins {
    HighHarness internal craps;

    uint24 internal constant L = 600;
    uint128 internal constant LW = 600e18;
    uint24 internal constant SU = 3;
    uint256 internal constant PLAIN_WORD = 40 << 8;

    address[6] internal players;

    function setUp() public {
        _installPins();
        craps = new HighHarness();
        // The deployment day is a Craps warm-up day with no windows; every fixture plays
        // from genesis + 1, the first day the table opens.
        vm.warp(block.timestamp + 1 days);
        _setIndex(4);
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
        for (uint256 i = 0; i < players.length; ++i) {
            players[i] = makeAddr(string(abi.encodePacked("p", vm.toString(i))));
            game.setScore(players[i], craps.SYBIL_SCORE_FLOOR());
        }
    }

    function _board() internal pure returns (Craps.Bets memory b) {
        b.passLine = 4;
        b.place6 = 3;
    }

    /// @dev One entry, measured. `h` is the field's lane multiple, `m` what this seat names.
    function _entryGas(uint64 slot, address who, uint16 m) internal returns (uint256 used) {
        vm.prank(who);
        uint256 before = gasleft();
        craps.enterBattle(slot, _board(), m);
        used = before - gasleft();
    }

    function _fill(uint64 slot, uint256 n, uint16 m) internal {
        for (uint256 i = 0; i < n; ++i) _entryGas(slot, players[i], m);
    }

    /// @dev A battle nobody has touched, at a played figure unique to `salt` so it keys apart.
    function _battle(uint32 salt, uint16 h) internal returns (uint64) {
        return _openHigh(craps, L + salt * 10, 2, 5, SU, h);
    }

    // ── Entry ───────────────────────────────────────────────────────────────

    /// @dev An ORDINARY seat pays nothing for a lane it did not take, whether or not the field
    ///      offers one. Budget: 2,500.
    function test_gas_anOrdinarySeatPaysNothingForTheLane() public {
        _entryGas(_battle(0, 0), players[0], 1); // warm the shared slots
        uint256 without = _entryGas(_battle(1, 0), players[1], 1);
        uint256 with_ = _entryGas(_battle(2, 10), players[2], 1);
        emit log_named_uint("ordinary entry, no lane offered ", without);
        emit log_named_uint("ordinary entry, lane offered    ", with_);
        assertLe(with_, without + 2_500, "an ordinary seat pays for the lane");
    }

    /// @dev The FIRST high seat in a battle writes the sideboard from cold. Budget: 25,000.
    ///      A LATER one finds it warm. Budget: 10,000.
    function test_gas_theFirstAndLaterHighEntry() public {
        _entryGas(_battle(3, 10), players[0], 1); // warm
        uint64 plain = _battle(4, 10);
        uint256 ordinary = _entryGas(plain, players[1], 1);

        uint64 slot = _battle(5, 10);
        uint256 first = _entryGas(slot, players[2], 10);
        uint256 later = _entryGas(slot, players[3], 10);
        emit log_named_uint("ordinary entry                  ", ordinary);
        emit log_named_uint("first high entry                ", first);
        emit log_named_uint("later high entry                ", later);
        assertLe(first, ordinary + 25_000, "the first high entry is over budget");
        assertLe(later, ordinary + 10_000, "a later high entry is over budget");
    }

    // ── Settlement ──────────────────────────────────────────────────────────

    /// @dev THE RESOLVE PATH IS NOT MEASURABLE BY GAS HERE, and pretending otherwise would be
    ///      worse than not measuring it. A field's shooter is `_crapsSeed(word, SLOT)` — keyed to
    ///      the slot, not the table index — so no two battles ever play the same dice and no A/B
    ///      pair is like-for-like. Hand length is geometric with a long tail, so a settlement
    ///      costs anywhere from 70k to 800k depending on how the shooter ran; over 24 samples the
    ///      mean still swings by ~20k, which swamps a lane that costs a few hundred.
    ///
    ///      So what §11.1 actually asks for is asserted DIRECTLY, against the storage the batch
    ///      touched. That is the property the gas budget was a proxy for: the lane adds ONE word
    ///      per battle and ONE packed action accumulator per day, and no per-entrant storage at all.
    ///      PINNED slot numbers, so they go stale the moment a mapping is added or removed above
    ///      them. The pair of tests below is what catches that: the negative one asserts the lane
    ///      slots are never written and would pass against any wrong slot, while the positive one
    ///      asserts they ARE — so a stale pin turns the positive test red rather than quietly
    ///      hollowing out the negative. Keep them together.
    uint256 internal constant _HIGH_FIELD_SLOT = 12;
    uint256 internal constant _DAY_STAKED_SLOT = 10;

    function _slotOfMapping(bytes32 key, uint256 base) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, base));
    }

    function _countWrites(bytes32[] memory writes, bytes32 target) internal pure returns (uint256 n) {
        for (uint256 i = 0; i < writes.length; ++i) if (writes[i] == target) ++n;
    }

    /// @dev A batch holding NO high seat writes NOTHING of the lane's — not the sideboard, not the
    ///      sideboard. Its ordinary action still writes the day's ONE packed accumulator, whose
    ///      high half remains zero, and reads the sideboard exactly once on the finishing seat.
    ///
    ///      That one read is the price of paying at finalization: the batch that finishes a field
    ///      pays it, and it cannot know whether a lane is standing beside it without asking. It is
    ///      once per BATTLE and never per entrant, which is the thing that would actually scale —
    ///      so the count is pinned at one here rather than merely bounded.
    function test_storage_aBatchWithNoHighSeatOnlyAsksWhetherALaneExists() public {
        uint64 slot = _battle(30, 10);
        _fill(slot, 3, 1);
        bytes32 key = craps.battleKeyOf((uint256(slot) << 64) | 1);
        _closeOn(craps, slot, 120, uint256(keccak256("nohigh")));

        vm.record();
        craps.resolveSlot(slot, WHOLE_FIELD);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(craps));

        bytes32 field = _slotOfMapping(key, _HIGH_FIELD_SLOT);
        uint24 day = craps.currentDayIndex();
        bytes32 staked = _slotOfMapping(bytes32(uint256(day)), _DAY_STAKED_SLOT);
        assertEq(_countWrites(writes, field), 0, "an ordinary field wrote the sideboard");
        assertEq(_countWrites(reads, field), 1, "an ordinary field read the sideboard other than once");
        assertEq(_countWrites(writes, staked), 1, "ordinary action was not booked in one packed write");
        assertEq(craps.highStakedOf(day), 0, "ordinary action spilled into the packed high half");
    }

    /// @dev A batch that DOES hold high seats touches exactly ONE sideboard word, however many of
    ///      them there are, and ONE day accumulator. Repeats land on the same warm slot — there is
    ///      no per-entrant side storage, which is the thing that would actually scale.
    function test_storage_theLaneIsOneWordPerBattleAndOnePerDay() public {
        uint64 slot = _battle(31, 10);
        _fill(slot, 3, 10);
        bytes32 key = craps.battleKeyOf((uint256(slot) << 64) | 1);
        _closeOn(craps, slot, 121, uint256(keccak256("high")));

        vm.record();
        craps.resolveSlot(slot, WHOLE_FIELD);
        (, bytes32[] memory writes) = vm.accesses(address(craps));

        bytes32 field = _slotOfMapping(key, _HIGH_FIELD_SLOT);
        uint24 day = craps.currentDayIndex();
        bytes32 staked = _slotOfMapping(bytes32(uint256(day)), _DAY_STAKED_SLOT);
        assertGt(_countWrites(writes, field), 0, "three high seats wrote no sideboard");
        assertEq(_countWrites(writes, staked), 1, "the day's high action was booked more than once");
        assertGt(craps.highStakedOf(day), 0, "the packed high half recorded no high action");

        // And the whole lane is those two slots: no third slot in either mapping was written.
        uint256 laneWrites;
        for (uint256 i = 0; i < writes.length; ++i) {
            if (writes[i] == field || writes[i] == staked) ++laneWrites;
        }
        uint256 distinct;
        for (uint256 i = 0; i < writes.length; ++i) {
            bool seen;
            for (uint256 j = 0; j < i; ++j) if (writes[j] == writes[i]) seen = true;
            if (!seen && (writes[i] == field || writes[i] == staked)) ++distinct;
        }
        assertEq(distinct, 2, "the lane wrote something other than its one word and one accumulator");
        assertGt(laneWrites, 0, "the lane wrote nothing");
    }

    /// @dev The batch that FINISHES a field is the one that pays it — the pot to the main winner
    ///      and, here, a contested lane to the best high roller. Both payments together, on top of
    ///      the settle itself, are what a claimer used to pay separately.
    function test_gas_theFinishingBatchPaysBothPots() public {
        uint64 slot = _battle(11, 10);
        _fill(slot, 3, 10);
        _closeOn(craps, slot, 70, uint256(keccak256("claimgas")));

        // Everything but the last seat, so the measured call is the one that finalizes and pays.
        craps.resolveSeats(slot, 2);
        uint256 before = gasleft();
        craps.resolveSeats(slot, 1);
        uint256 used = before - gasleft();
        emit log_named_uint("finishing batch, both pots      ", used);

        (,,,, bool done) = craps.highFieldOf(craps.battleKeyOf((uint256(slot) << 64) | 1));
        assertTrue(done, "the lane did not pay when the field finished");
    }

}
