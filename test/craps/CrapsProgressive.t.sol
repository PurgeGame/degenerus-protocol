// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsViews} from "./CrapsViews.sol";
import {Vm} from "forge-std/Vm.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Taps for the progressive alone. Every one of them drives a SHIPPED internal — the fold
///      that stores a winner's composite, the award branch a finalization runs, the rollover a
///      rationed subsidy takes — so nothing here is a second implementation of a rule.
contract ProgHarness is CrapsViews {
    function bookDay(uint24 day, uint256 staked) external {
        _bookDay(day, staked, 0);
    }

    function bookHighDay(uint24 day, uint256 staked) external {
        _bookDay(day, staked, staked);
    }

    /// @dev The shipped fold. Production reaches it once per settled seat; a suite reaches it
    ///      directly so the scoreboard's packing can be graded without running a field through
    ///      the engine to produce one particular high point. `slot` decides which product's
    ///      comparator the fold stamps the word with.
    function scoreAt(bytes32 key, uint256 score, uint64 seat, uint256 stakeUnits, uint64 slot) external {
        Window memory w;
        w.key = key;
        w.stakeUnits = stakeUnits;
        w.bound = uint48(slot);
        // A REAL SCHEDULED SHAPE, because the fold pays the field the moment it completes it —
        // 3,000 FLIP five rounds deep chasing 5x.
        w.bankroll = 3000 ether;
        w.goal = 15_000 ether;
        w.played = 600 ether;
        _scoreBattle(w, score, seat, 0);
    }

    /// @dev The composite a SCHEDULED goal folds, built through the shipped comparator: the goal
    ///      flag, the high point in whole FLIP, the ending bankroll, the standing.
    function goalScore(uint256 peakFlip, uint256 endFlip, uint256 standing) external pure returns (uint256) {
        Settlement memory s;
        s.stop = Craps.SlipStop.Goal;
        s.peak = peakFlip * 1 ether;
        s.won = endFlip * 1 ether;
        return _compositeOf(s) | standing;
    }

    /// @dev The composite a BUST folds: shooters completed, then the remainder.
    function bustScore(uint256 hands, uint256 endFlip, uint256 standing) external pure returns (uint256) {
        Settlement memory s;
        s.stop = Craps.SlipStop.Bust;
        s.handsPlayed = hands;
        s.won = endFlip * 1 ether;
        s.peak = 1e30; // a bust's peak must reach neither field
        return _compositeOf(s) | standing;
    }

    /// @dev THE AWARD BRANCH, on a synthesized finalized scoreboard, driven the way `_payout`
    ///      drives it: the shipped comparator builds the composite, the shipped decoder reads the
    ///      high point back out of it, and the shipped award reads that high point. So the custom
    ///      boundary and the bust gate are exercised here as STRUCTURE — a bust and a custom both
    ///      arrive at the award with a zero peak — rather than restated as a condition.
    ///
    ///      The window is a real scheduled format: a slot below the custom base, and a (bankroll,
    ///      round, goal) triple the schedule can actually draw.
    function awardAt(
        uint64 slot,
        uint256 bankrollFlip,
        bool goal,
        uint256 peakFlip,
        uint256 standing,
        address winner
    ) external returns (uint256 credited) {
        Window memory w;
        w.bound = uint48(slot);
        w.key = keccak256(abi.encode("prog", slot, bankrollFlip, peakFlip, standing));
        w.bankroll = uint128(bankrollFlip * 1 ether);
        w.played = (bankrollFlip / SCHED_BANK_MULT) * 1 ether;
        w.goal = uint128(bankrollFlip * SCHED_GOAL * 1 ether);

        Settlement memory st;
        st.stop = goal ? Craps.SlipStop.Goal : Craps.SlipStop.Bust;
        st.peak = peakFlip * 1 ether;
        st.handsPlayed = 7;
        (,, uint256 peak,) = _decodeBest(_compositeOf(st));

        uint256 before = _progressive;
        uint256 winnerWord = uint256(uint160(winner)) | (standing << _BET_SCORE_SHIFT);
        if (w.bound < _CUSTOM_SLOT_BASE) {
            _payProgressive(
                w, peak, (peak * BPS_DENOMINATOR) / bankrollFlip, (uint256(slot) << 64) | 1, winnerWord, winner
            );
        }
        credited = before - _progressive;
    }

    function rollIn(bytes32 key, uint8 source, uint256 amount) external {
        _rollIn(key, (uint256(source) << 248) | amount);
    }

    function settlementAt(uint256 betId) external view returns (Settlement memory) {
        return _settlementOf(betId, _bets[betId], _slotWindow(betId >> 64), _wordAt(_indexOf(betId >> 64)));
    }

    function settlementIn(uint256 betId, uint64 slot) external view returns (Settlement memory) {
        return _settlementOf(betId, _bets[betId], _slotWindow(slot), _wordAt(_indexOf(slot)));
    }

    /// @dev The RAW scoreboard word, and a raw writer for it. The packing claim — a 105-bit
    ///      composite and a 32-bit seat above it — is only really graded against the bits
    ///      themselves.
    function battleWordOf(bytes32 key) external view returns (uint256) {
        return _battles[key];
    }

    function writeBattleWord(bytes32 key, uint256 word) external {
        _battles[key] = word;
    }


    /// @dev The composite's raw shape, so a fixture can place one field at a time.
    function rawComposite(bool goal, uint256 primary, uint256 wonFlip, uint256 standing)
        external
        pure
        returns (uint256)
    {
        return (goal ? _SC_GOAL_BIT : 0) | ((primary & _SC_PRIMARY_MASK) << _SC_PRIMARY_SHIFT)
            | ((wonFlip & _SC_WON_MASK) << _SC_WON_SHIFT) | standing;
    }

    function boostUnitsAt(uint64 slot) external view returns (uint256) {
        Window memory w = _slotWindow(slot);
        return _boostUnits(w, _wordAt(_indexOf(slot)));
    }

    function roundBoostFor(uint256 units) external pure returns (uint256) {
        return _roundBoost(units);
    }

    function customSlotBase() external pure returns (uint256) {
        return _CUSTOM_SLOT_BASE;
    }

    function winnerRegionShift() external pure returns (uint256 winnerShift, uint256 primaryMask) {
        return (_BG_WINNER_SHIFT, _SC_PRIMARY_MASK);
    }

    function _daySlotOfPub(uint24 day) public pure returns (uint256) {
        return uint256(day) * BONUS_SLOTS_PER_DAY;
    }

    /// @dev The fractional copy a sole rider's capital comes home on, so a fixture can assert what
    ///      rode without restating the arithmetic that decides it.
    function rideOf(uint256 paid, uint256 capital, uint256 bankroll) external pure returns (uint256) {
        return _ride(paid, capital, bankroll);
    }

    /// @dev The composite the fold is currently holding, whether or not the field has finished.
    function leaderBestOf(bytes32 key) external view returns (uint256) {
        return (_battles[key] >> _BG_BEST_SHIFT) & _SC_BEST_MASK;
    }

    /// @dev The high point the fold is currently holding, in whole FLIP.
    function leaderPeakOf(bytes32 key) external view returns (uint256) {
        return ((_battles[key] >> _BG_BEST_SHIFT) >> _SC_PRIMARY_SHIFT) & _SC_PRIMARY_MASK;
    }
}

/// @title The Craps progressive
/// @notice One pool, funded by half of every opened day's main allocation and by every wei of the
///         protocol's own subsidy an activity score would not admit, paid out to the winner a
///         scheduled field already named when that winner's HIGH POINT clears its format's
///         cutoff.
contract CrapsProgressiveTest is CrapsPins {
    ProgHarness internal craps;

    uint256 internal constant PLAIN_WORD = 40 << 8;

    /// @dev The two progressive log signatures, named once. Spelled out at every site they would
    ///      wrap past the line budget and read as noise rather than as an assertion.
    bytes32 internal constant _PAID_SIG = keccak256(
        "CrapsProgressivePaid(uint256,bytes32,address,bool,uint16,uint256,uint256,uint256,uint256,uint256)"
    );
    bytes32 internal constant _ROLLED_SIG = keccak256("CrapsProgressiveRolled(bytes32,uint8,uint256,uint256)");
    uint256 internal constant PER = 1;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    /// @dev A scheduled slot far from any this suite opens for real, for the taps that only need
    ///      the branch to believe it is looking at a protocol window. Slots run
    ///      `day * 8 + period + 1`, so 9 is day 1 period 0 — a ROUTINE window.
    uint64 internal constant TAP_SLOT = 9;
    /// @dev The EVENT of TAP_SLOT's own day: day 1, period 6, remainder 7.
    uint64 internal constant TAP_EVENT_SLOT = 15;
    /// @dev A routine window and an event on a DIFFERENT day (day 2), for the staleness cases.
    uint64 internal constant TAP_SLOT_DAY2 = 17;
    uint64 internal constant TAP_EVENT_SLOT_DAY2 = 23;

    /// @dev The bankroll every award tap runs at, in whole FLIP. Its 25x common cutoff is 75,000
    ///      FLIP and its 120x rare cutoff is 360,000 — both exact.
    uint256 internal constant TAP_BANKROLL = 3000;

    function setUp() public {
        _installPins();
        craps = new ProgHarness();
        // The deployment day is a Craps warm-up day with no windows; every fixture plays
        // from genesis + 1, the first day the table opens.
        vm.warp(block.timestamp + 1 days);
        _setIndex(4);
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
    }

    function _openDay() internal {
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
    }

    function _slotAt(uint256 period) internal view returns (uint64) {
        (uint24 day,,) = craps.currentBonusSlot();
        return uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + period + 1);
    }

    function _keyOf(uint256 period) internal view returns (bytes32) {
        return craps.keyOfSlot(_slotAt(period));
    }

    // ════════════════════════════════════════════════════════════════════════
    // A. THE SPLIT — what a day raises, and where the two halves go.
    // ════════════════════════════════════════════════════════════════════════

    /// @dev ZERO ACTION: the raw allocation is exactly the base, and it halves exactly.
    function test_aColdDayRaisesFiftyThousandAndSplitsItInHalf() public {
        vm.warp(vm.getBlockTimestamp() + 10 days);
        uint24 today = craps.currentDayIndex();
        (uint256 raw, uint256 high) = craps.drawBudgetsFor(today);
        assertEq(raw, 50_000 ether, "a cold day did not raise 50,000 FLIP");
        assertEq(high, 0, "a cold day funded a high lane");

        (uint256 ladder, uint256 contribution) = craps.splitMainBudget(raw);
        assertEq(ladder, 25_000 ether, "the ladder half is not 25,000 FLIP");
        assertEq(contribution, 25_000 ether, "the progressive contribution is not 25,000 FLIP");
    }

    /// @dev THE CONSERVATION LAW, on every residue. `ladder + progressive == raw` for the odd
    ///      figure as well as the even one — the ladder is floored, so the stray wei is the
    ///      pool's, and neither half ever rounds a wei into existence.
    function test_theSplitConservesTheRawAllocationIncludingTheOddWei(uint256 raw) public view {
        raw = bound(raw, 0, type(uint128).max);
        (uint256 ladder, uint256 contribution) = craps.splitMainBudget(raw);
        assertEq(ladder + contribution, raw, "the split lost or created a wei");
        assertEq(ladder, raw / 2, "the ladder is not the floored half");
        assertLe(ladder, contribution, "the odd wei did not go to the pool");
        assertLe(contribution - ladder, 1, "the two halves are more than a wei apart");
    }

    /// @dev THE RATE IS UNTOUCHED. Twelve percent across both lanes, the high lane's own component
    ///      split 2:3, and no wei of action reaching both — exactly as before the base moved. Only
    ///      the base itself changed, and only the MAIN allocation is split.
    function test_theTwelvePercentRateAndTheHighLaneAreUnchanged() public {
        vm.warp(vm.getBlockTimestamp() + 10 days);
        uint24 today = craps.currentDayIndex();
        uint256 days_ = craps.BOOST_ACTION_WINDOW_DAYS();
        uint256 base = craps.BASE_MAIN_BUDGET();
        uint256 perDay = 7_000_000 ether;

        for (uint256 i = 1; i <= days_; ++i) craps.bookDay(today - uint24(i), perDay);
        (uint256 m, uint256 h) = craps.drawBudgetsFor(today);
        assertEq(m, base + perDay * 12 / 100, "regular action is not worth 12% to the main lane");
        assertEq(h, 0, "regular action funded the high lane");

        uint24 later = today + uint24(days_);
        for (uint256 i = 1; i <= days_; ++i) craps.bookHighDay(later - uint24(i), perDay);
        (m, h) = craps.drawBudgetsFor(later);
        assertEq(m, base + perDay * 48 / 1000, "high action is not worth 4.8% to the main lane");
        assertEq(h, perDay * 72 / 1000, "high action is not worth 7.2% to its own lane");
        assertEq((m - base) + h, perDay * 12 / 100, "the two lanes do not sum to 12% of the action");

        // AND THE HIGH BUDGET IS NEVER SPLIT. What a day banks in the high lane is the whole
        // figure `_drawBudgets` returned; only its standing forfeitures ever leave it.
        _setDailyWord(later, PLAIN_WORD);
        vm.warp(vm.getBlockTimestamp() + uint256(days_) * 1 days);
        assertEq(craps.currentDayIndex(), later, "the fixture did not land on the funded day");
        _openDay();
        assertEq(craps.highBudgetOf(later), h, "the high budget was split or moved");
        assertEq(craps.boostBudgetOf(later), m / 2, "the ladder is not half the raw main allocation");
        assertEq(craps.progressivePool(), m - m / 2, "the pool did not take the other half");
    }

    /// @dev A DAY FUNDS THE POOL ONCE. `openBonusDay` is permissionless in effect — the advance
    ///      calls it every crank — and arming is permissionless outright, so the guard is what
    ///      stops the pool being topped up by whoever calls the most.
    function test_aDayFundsTheProgressiveExactlyOnce() public {
        uint24 today = craps.currentDayIndex();
        _openDay();
        uint256 once = craps.progressivePool();
        assertGt(once, 0, "the day funded nothing");

        for (uint256 i = 0; i < 5; ++i) _openDay();
        assertEq(craps.progressivePool(), once, "repeated opens funded the pool again");

        // Arming every window of the day, in any order, adds nothing either.
        vm.warp(vm.getBlockTimestamp() + 1 days);
        for (uint256 p = 0; p < craps.BONUS_PERIODS_PER_DAY(); ++p) {
            craps.armBonusWindow(uint64(uint256(today) * craps.BONUS_SLOTS_PER_DAY() + p + 1));
        }
        assertEq(craps.progressivePool(), once, "arming funded the pool");
    }

    /// @dev A PRE-OPEN QUOTE ADVERTISES THE LADDER, not the raw allocation. Both the quote and the
    ///      opening go through one helper, so a window cannot be shown twice what it will hold.
    function test_aPreOpenQuoteAdvertisesTheLadderHalf() public {
        vm.warp(vm.getBlockTimestamp() + 10 days);
        uint24 today = craps.currentDayIndex();
        uint256 days_ = craps.BOOST_ACTION_WINDOW_DAYS();
        for (uint256 i = 1; i <= days_; ++i) craps.bookDay(today - uint24(i), 3_600_000 ether);
        _setDailyWord(today, PLAIN_WORD);

        // Quoted BEFORE the day opens: every window's share, and the event's, off the ladder half.
        uint256 ladder = craps.ladderBudgetFor(today);
        (uint256 raw,) = craps.drawBudgetsFor(today);
        assertEq(ladder, raw / 2, "the pre-open quote is not the ladder half");

        uint256 periods = craps.BONUS_PERIODS_PER_DAY();
        uint256[] memory quoted = new uint256[](periods);
        uint256 sum;
        for (uint256 p = 0; p < periods; ++p) {
            quoted[p] = craps.boostBaseOf(uint64(uint256(today) * craps.BONUS_SLOTS_PER_DAY() + p + 1));
            sum += quoted[p];
        }
        assertApproxEqAbs(sum, ladder, periods, "the pre-open quotes do not partition the ladder");

        // And the same figures after it opens, off the STORED budget rather than a redraw.
        _openDay();
        assertEq(craps.boostBudgetOf(today), ladder, "the day stored other than the ladder");
        assertEq(craps.progressiveContributionFor(today), raw - ladder, "the contribution quote moved");
        for (uint256 p = 0; p < periods; ++p) {
            assertEq(
                craps.boostBaseOf(uint64(uint256(today) * craps.BONUS_SLOTS_PER_DAY() + p + 1)),
                quoted[p],
                "a window's share moved when its day opened"
            );
        }
    }

    /// @dev THE FUNDING LOG carries what an indexer needs and agrees with the day-opened log.
    function test_theFundingLogAndTheDayOpenedLogAgree() public {
        uint24 today = craps.currentDayIndex();
        (uint256 raw,) = craps.drawBudgetsFor(today);
        vm.recordLogs();
        _openDay();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 fundSig = keccak256("CrapsProgressiveFunded(uint24,uint256,uint256)");
        bytes32 openSig = keccak256("CrapsHighRollerDayOpened(uint24,uint16,uint256,uint256)");
        uint256 funded;
        uint256 laddered;
        uint256 seen;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] == fundSig) {
                assertEq(uint256(logs[i].topics[1]), today, "the funding log named another day");
                (uint256 contribution, uint256 balance) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(balance, contribution, "the first day's balance is not its own contribution");
                funded = contribution;
                ++seen;
            } else if (logs[i].topics[0] == openSig) {
                (, uint256 main,) = abi.decode(logs[i].data, (uint16, uint256, uint256));
                laddered = main;
            }
        }
        assertEq(seen, 1, "a day emitted other than one funding log");
        assertEq(funded + laddered, raw, "the two logs do not reconstruct the raw allocation");
        assertEq(craps.progressivePool(), funded, "the pool disagrees with its own log");
    }

    // ════════════════════════════════════════════════════════════════════════
    // B. THE CUTOFFS — every threshold, from both sides.
    // ════════════════════════════════════════════════════════════════════════

    /// @dev THE PUBLISHED PAIR, restated as literals so the constants are graded against the
    ///      specification rather than against itself.
    function test_theScheduledFormatCarriesThePublishedCutoffs() public view {
        // In SCORE BASIS POINTS, which is how the award compares them: 10,000 is 1x.
        (uint256 c, uint256 r) = craps.progressiveThresholds();
        assertEq(c, 250_000, "the common cutoff is off the published pair");
        assertEq(r, 1_200_000, "the rare cutoff is off the published pair");
        assertGt(r, c, "the rare cutoff does not sit above the common one");
        assertGt(c, craps.SCHED_GOAL() * craps.BPS_DENOMINATOR(), "the common cutoff is not above the target");
    }

    /// @dev BOTH CUTOFFS FROM BOTH SIDES. One FLIP below a cutoff is the rung below it; the
    ///      cutoff is inclusive.
    function test_eachCutoffIsInclusiveAndOneFlipBelowItIsNot() public {
        uint256 pool = 1_000_000 ether;
        // TAP_SLOT is a ROUTINE window, so these are the 5% and 10% rungs.
        uint256 ROUTINE_COMMON = craps.poolShareOf(pool, craps.PROG_ROUTINE_COMMON_BPS());
        uint256 ROUTINE_RARE = craps.poolShareOf(pool, craps.PROG_ROUTINE_RARE_BPS());
        (uint256 cm, uint256 rm) = craps.progressiveThresholds();
        // The cutoffs are in SCORE BASIS POINTS; the tap's own bankroll turns them into whole
        // FLIP, and every scheduled bankroll is a whole-FLIP multiple of 300 so both land
        // exactly on a whole FLIP rather than between two.
        uint256 c = (TAP_BANKROLL * cm) / craps.BPS_DENOMINATOR();
        uint256 r = (TAP_BANKROLL * rm) / craps.BPS_DENOMINATOR();
        assertEq((TAP_BANKROLL * cm) % craps.BPS_DENOMINATOR(), 0, "the common cutoff is not a whole FLIP");
        assertEq((TAP_BANKROLL * rm) % craps.BPS_DENOMINATOR(), 0, "the rare cutoff is not a whole FLIP");

        assertEq(_awardWith(pool, c - 1, 12), 0, "a high point below common paid");
        assertEq(_awardWith(pool, c, 12), ROUTINE_COMMON, "the common cutoff did not pay the common rung");
        assertEq(_awardWith(pool, r - 1, 12), ROUTINE_COMMON, "one FLIP below rare is not the common rung");
        assertEq(_awardWith(pool, r, 12), ROUTINE_RARE, "the rare cutoff did not pay the rare rung");
    }

    /// @dev RARE OVERRIDES, it does not stack. A run that clears the rare cutoff has cleared the
    ///      common one too, and takes the half ALONE.
    function test_rareOverridesCommonAndNeverPaysBoth() public {
        uint256 pool = 1_000_000 ether;
        uint256 ROUTINE_RARE = craps.poolShareOf(pool, craps.PROG_ROUTINE_RARE_BPS());
        (uint256 c, uint256 r) = craps.progressiveThresholds();
        assertGt(r, c, "the fixture's rare cutoff is not above its common one");
        uint256 rFlip = (TAP_BANKROLL * r) / craps.BPS_DENOMINATOR();

        craps.seedProgressive(pool);
        vm.recordLogs();
        craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, rFlip, 12, alice);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 awards;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] != _PAID_SIG) continue;
            (bool rare, uint16 poolBps, uint256 peak, uint256 scoreBps,, uint256 paid,) =
                abi.decode(logs[i].data, (bool, uint16, uint256, uint256, uint256, uint256, uint256));
            assertTrue(rare, "the rare cutoff logged a common award");
            assertEq(poolBps, craps.PROG_ROUTINE_RARE_BPS(), "the routine rare rung is not 10%");
            assertEq(peak, rFlip, "the log restated another high point");
            assertEq(scoreBps, r, "the logged multiple is not the peak over the start");
            assertEq(paid, ROUTINE_RARE, "the rare award is not the routine rare rung");
            ++awards;
        }
        assertEq(awards, 1, "a rare result emitted other than one award");
        assertEq(craps.progressivePool(), pool - ROUTINE_RARE, "the pool paid more than the rare rung");
    }

    /// @dev A GOAL BELOW THE COMMON CUTOFF PAYS NOTHING, and a BUST PAYS NOTHING however high it
    ///      got — past the rare cutoff included. A bust's peak reaches the composite's primary
    ///      field in neither product, so the stop is a structural gate rather than a tiebreak.
    function test_aShortGoalAndAHighBustBothPayNothing() public {
        uint256 pool = 900_000 ether;
        (uint256 c, uint256 r) = craps.progressiveThresholds();

        uint256 cFlip = (TAP_BANKROLL * c) / craps.BPS_DENOMINATOR();
        uint256 rFlip = (TAP_BANKROLL * r) / craps.BPS_DENOMINATOR();
        assertEq(_awardWith(pool, cFlip - 1, 12), 0, "a goal below the common cutoff paid");
        assertEq(_awardWith(pool, 0, 12), 0, "a goal with no high point paid");

        craps.seedProgressive(pool);
        assertEq(
            craps.awardAt(TAP_SLOT, TAP_BANKROLL, false, rFlip + TAP_BANKROLL * 500, 12, alice),
            0,
            "a bust that had been far above the rare cutoff drew on the pool"
        );
        assertEq(craps.progressivePool(), pool, "a bust moved the pool");
    }

    /// @dev A CUSTOM BATTLE IS OUTSIDE THE POOL IN BOTH DIRECTIONS: it never funds it and it never
    ///      draws on it, whatever its terms and however long its winner ran.
    function test_aCustomBattleNeitherFundsNorDrawsOnThePool() public {
        uint256 pool = 500_000 ether;
        craps.seedProgressive(pool);
        uint64 customSlot = uint64(craps.customSlotBase() + 1);
        assertEq(
            craps.awardAt(customSlot, TAP_BANKROLL, true, TAP_BANKROLL * 400, 12, alice),
            0,
            "a custom battle drew on the pool"
        );
        assertEq(craps.progressivePool(), pool, "a custom battle moved the pool");

        // And a real one, settled end to end, moves nothing either.
        uint64 slot = _openBattle(craps, 600, 2, 5, 3);
        vm.prank(alice);
        craps.enterBattle(slot, 3 | (uint32(3) << 9) | (uint32(1) << 12), 1);
        vm.prank(bob);
        craps.enterBattle(slot, 3 | (uint32(3) << 12) | (uint32(1) << 15), 1);
        _closeOn(craps, slot, 7, uint256(keccak256("custom-word")));
        craps.resolveSlot(slot, WHOLE_FIELD);
        assertEq(craps.progressivePool(), pool, "settling a custom battle moved the pool");
    }

    /// @dev SEQUENTIAL AWARDS EAT THE LIVE BALANCE. No day's contribution is reserved for a window
    ///      and no snapshot is taken: the second award is a share of what the first left.
    function test_sequentialAwardsUseTheReducedLiveBalance() public {
        craps.seedProgressive(1_000_000 ether);
        // Both taps are ROUTINE windows: 10% of a million, then 5% of the 900,000 it left.
        assertEq(
            craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, TAP_BANKROLL * 120, 12, alice),
            100_000 ether,
            "the rare rung is wrong"
        );
        assertEq(craps.progressivePool(), 900_000 ether, "the pool is not what the rare rung left");
        assertEq(
            craps.awardAt(TAP_SLOT + 1, TAP_BANKROLL, true, TAP_BANKROLL * 25, 12, bob),
            45_000 ether,
            "the common rung is wrong"
        );
        assertEq(craps.progressivePool(), 855_000 ether, "the pool is not what the common rung left");
        assertEq(
            craps.awardAt(TAP_SLOT + 2, TAP_BANKROLL, true, TAP_BANKROLL * 120, 12, carol),
            85_500 ether,
            "the third rung is wrong"
        );
        assertEq(craps.progressivePool(), 769_500 ether, "funding minus payouts is not the pool");
    }

    /// @dev INTEGER DIVISION CANNOT OVERDRAW, and a pool too small to pay a rung produces a zero
    ///      award and NO cross-contract call at all.
    function test_aTinyPoolPaysZeroWithoutAnExternalCall(uint96 pool) public {
        craps.seedProgressive(pool);
        uint256 before = coinflip.credits();
        uint256 credited = craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, TAP_BANKROLL * 25, 12, alice);
        assertLe(credited, pool, "the award overdrew the pool");
        assertEq(
            credited,
            craps.poolShareOf(pool, craps.PROG_ROUTINE_COMMON_BPS()),
            "the common rung is not the floored routine share"
        );
        assertEq(craps.progressivePool(), uint256(pool) - credited, "the pool did not fall by exactly the credit");
        if (credited == 0) {
            assertEq(coinflip.credits(), before, "a zero award still called coinflip");
        } else {
            assertEq(coinflip.credits(), before + 1, "a paying award did not credit exactly once");
        }
    }

    /// @dev The pool can be emptied and re-funded without anything special happening: an empty
    ///      pool simply has no rung, and the next day's contribution starts it again.
    function test_anEmptyPoolIsSafeAndRefundable() public {
        craps.seedProgressive(0);
        assertEq(craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, TAP_BANKROLL * 120, 12, alice), 0, "an empty pool paid");
        assertEq(craps.progressivePool(), 0, "an empty pool moved");

        _openDay();
        assertGt(craps.progressivePool(), 0, "the pool did not refund on the next opened day");
    }

    // ════════════════════════════════════════════════════════════════════════
    // B2. THE RUNG SCHEDULE — which share of the pool, and when it doubles.
    // ════════════════════════════════════════════════════════════════════════

    /// @dev A peak that clears the scheduled target's COMMON cutoff and nothing more, and one
    ///      that clears its RARE cutoff. Both at TAP_BANKROLL, so a fixture can name a rung without
    ///      restating the cutoff table beside it.
    uint256 internal constant COMMON_PEAK = TAP_BANKROLL * 25;
    uint256 internal constant RARE_PEAK = TAP_BANKROLL * 120;

    /// @dev Award on `slot` at full standing, off a freshly seeded pool, and give back the credit.
    function _rungAt(uint64 slot, uint256 pool, uint256 peakFlip) internal returns (uint256) {
        craps.seedProgressive(pool);
        return craps.awardAt(slot, TAP_BANKROLL, true, peakFlip, craps.SYBIL_SCORE_FLOOR(), alice);
    }

    /// @dev ALL FOUR BASE RUNGS, against the published schedule stated as literals rather than as
    ///      the constants the award reads — so the schedule is graded, not restated.
    ///
    ///        routine (periods 0..5)   5% common   10% rare
    ///        event   (period 6)      20% common   40% rare
    function test_allFourBaseRungsAreTheirPublishedShares() public {
        uint256 pool = 1_000_000 ether;
        assertEq(_rungAt(TAP_SLOT, pool, COMMON_PEAK), 50_000 ether, "a routine common rung is not 5%");
        assertEq(_rungAt(TAP_SLOT, pool, RARE_PEAK), 100_000 ether, "a routine rare rung is not 10%");
        assertEq(_rungAt(TAP_EVENT_SLOT, pool, COMMON_PEAK), 200_000 ether, "an event common rung is not 20%");
        assertEq(_rungAt(TAP_EVENT_SLOT, pool, RARE_PEAK), 400_000 ether, "an event rare rung is not 40%");

        // And the constants agree with the literals above, so a reader of either finds the same
        // schedule.
        assertEq(craps.PROG_ROUTINE_COMMON_BPS(), 500, "the routine common constant moved");
        assertEq(craps.PROG_ROUTINE_RARE_BPS(), 1000, "the routine rare constant moved");
        assertEq(craps.PROG_EVENT_COMMON_BPS(), 2000, "the event common constant moved");
        assertEq(craps.PROG_EVENT_RARE_BPS(), 4000, "the event rare constant moved");

        // THE TWO STATEMENTS OF THE SCHEDULE, HELD TOGETHER. The award computes
        // `_PROG_ROUTINE_COMMON_BPS << shift`; the four named rungs are the same table written
        // out, and the parity gate greps THOSE. A shift form that drifted from the names would
        // leave the gate green and the award paying something else.
        uint256 base = craps.PROG_ROUTINE_COMMON_BPS();
        uint256 rd = craps.PROG_RARE_DOUBLINGS();
        uint256 ed = craps.PROG_EVENT_DOUBLINGS();
        assertEq(base << rd, craps.PROG_ROUTINE_RARE_BPS(), "rare is not its named rung by doubling");
        assertEq(base << ed, craps.PROG_EVENT_COMMON_BPS(), "the event is not its named rung by doubling");
        assertEq(base << (rd + ed), craps.PROG_EVENT_RARE_BPS(), "the event rare rung is not its named one");
    }

    /// @dev THE REPEAT DOUBLE, at BOTH event rungs: 20% becomes 40% and 40% becomes 80%. The
    ///      qualifying win is a routine field on the SAME day, taken as Goal by the same address.
    function test_theEventDoublesOnARepeatVictoryAtBothRungs() public {
        uint256 pool = 1_000_000 ether;
        craps.noteRoutineVictory(TAP_SLOT, true, alice);
        assertEq(_rungAt(TAP_EVENT_SLOT, pool, COMMON_PEAK), 400_000 ether, "a doubled common event rung is not 40%");
        assertEq(_rungAt(TAP_EVENT_SLOT, pool, RARE_PEAK), 800_000 ether, "a doubled rare event rung is not 80%");

        // AND THE DOUBLING IS OBSERVABLE. `poolBps` carries the rung actually applied, so an
        // indexer reads the repeat status straight off the award — and read WITH `rare` it is
        // unambiguous, which is the case a bare 4,000 could not settle on its own.
        craps.seedProgressive(pool);
        vm.recordLogs();
        craps.awardAt(TAP_EVENT_SLOT, TAP_BANKROLL, true, COMMON_PEAK, craps.SYBIL_SCORE_FLOOR(), alice);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool seen;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] != _PAID_SIG) continue;
            (bool rare, uint16 poolBps,,, uint256 candidate,,) =
                abi.decode(logs[i].data, (bool, uint16, uint256, uint256, uint256, uint256, uint256));
            assertFalse(rare, "a 25x high point is not rare");
            assertEq(poolBps, 4000, "a doubled COMMON event rung did not log 4,000 bps");
            assertEq(candidate, 400_000 ether, "the logged candidate is not the doubled rung");
            seen = true;
        }
        assertTrue(seen, "the doubled award was not logged");
    }

    /// @dev A ROUTINE WINDOW NEVER DOUBLES, and that is the rule most easily got wrong: the 5%
    ///      and 10% rungs are the routine schedule, NOT a first-win rate that a repeat lifts. A
    ///      winner sitting on a qualifying victory takes exactly the same routine rung as one
    ///      who has never won anything.
    function test_aRoutineWindowNeverDoublesHoweverItsWinnerCameToIt() public {
        uint256 pool = 1_000_000 ether;
        craps.noteRoutineVictory(TAP_SLOT, true, alice);
        assertEq(craps.routineGoalDayOf(alice), 2, "the fixture did not stamp the day");
        // A SECOND routine victory the same day, so the map is as set as it can be.
        craps.noteRoutineVictory(TAP_SLOT + 1, true, alice);
        assertEq(_rungAt(TAP_SLOT + 2, pool, COMMON_PEAK), 50_000 ether, "a routine common rung doubled");
        assertEq(_rungAt(TAP_SLOT + 2, pool, RARE_PEAK), 100_000 ether, "a routine rare rung doubled");
    }

    /// @dev THE THREE WAYS A QUALIFYING VICTORY IS NOT ONE — each moved one step off a victory
    ///      that WOULD qualify, so the fixture is a control and not a coincidence.
    function test_aBustADifferentPlayerAndADifferentDayAllFailToQualify() public {
        uint256 pool = 1_000_000 ether;

        // A BUST, however far it ran. `noteRoutineVictory` is the shipped gate, so this is
        // production's own stop test.
        craps.noteRoutineVictory(TAP_SLOT, false, alice);
        assertEq(craps.routineGoalDayOf(alice), 0, "a bust stamped the day");
        assertEq(_rungAt(TAP_EVENT_SLOT, pool, RARE_PEAK), 400_000 ether, "a bust doubled the event");

        // A DIFFERENT PLAYER. Bob's victory is real; alice's event is not doubled by it.
        craps.noteRoutineVictory(TAP_SLOT, true, bob);
        assertEq(_rungAt(TAP_EVENT_SLOT, pool, RARE_PEAK), 400_000 ether, "another player's win doubled the event");

        // A DIFFERENT DAY. Alice wins a routine field on day 1 and reaches day 2's event, whose
        // slot carries day 2 — the stamp is stale and reads as never having won.
        craps.noteRoutineVictory(TAP_SLOT, true, alice);
        assertEq(_rungAt(TAP_EVENT_SLOT_DAY2, pool, RARE_PEAK), 400_000 ether, "a stale day doubled the event");
        // And on its OWN day it still doubles, so the fixture above failed on the day and on
        // nothing else.
        assertEq(_rungAt(TAP_EVENT_SLOT, pool, RARE_PEAK), 800_000 ether, "the control did not double");
    }

    /// @dev A QUALIFYING VICTORY NEED NOT HAVE TRIGGERED THE PROGRESSIVE. The stamp is written on
    ///      the VICTORY and not on the award, so a routine winner whose own peak fell short of
    ///      every cutoff — and which therefore paid nothing and left the pool alone — still
    ///      doubles its day's event.
    function test_anEarlierGoalVictoryThatPaidNothingStillQualifies() public {
        uint256 pool = 1_000_000 ether;
        craps.seedProgressive(pool);

        // A Goal just BELOW the scheduled target's common cutoff: no award, no movement.
        (uint256 c,) = craps.progressiveThresholds();
        uint256 shortPeak = (TAP_BANKROLL * c) / craps.BPS_DENOMINATOR() - 1;
        assertEq(
            craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, shortPeak, craps.SYBIL_SCORE_FLOOR(), alice),
            0,
            "the fixture's earlier victory paid a rung"
        );
        assertEq(craps.progressivePool(), pool, "the fixture's earlier victory moved the pool");

        // The victory is what qualifies, so the event still doubles.
        craps.noteRoutineVictory(TAP_SLOT, true, alice);
        assertEq(_rungAt(TAP_EVENT_SLOT, pool, RARE_PEAK), 800_000 ether, "a non-paying victory did not qualify");
    }

    /// @dev THE EVENT CANNOT QUALIFY ITSELF, and the gate is structural: only routine slots ever
    ///      write the map, so an event finalization leaves it exactly as it found it.
    function test_theEventCannotQualifyItself() public {
        craps.noteRoutineVictory(TAP_EVENT_SLOT, true, alice);
        assertEq(craps.routineGoalDayOf(alice), 0, "the event stamped its own winner");
        assertEq(
            _rungAt(TAP_EVENT_SLOT, 1_000_000 ether, RARE_PEAK), 400_000 ether, "the event doubled off its own win"
        );
    }

    /// @dev REPEAT VICTORIES NEVER STACK. The rule is a DOUBLING, not a count: six routine wins
    ///      pay the same doubled event rung one does, and 80% is the ceiling of the whole schedule.
    function test_repeatVictoriesNeverStackPastADoubling() public {
        uint256 pool = 1_000_000 ether;
        for (uint256 p = 0; p < 6; ++p) {
            craps.noteRoutineVictory(uint64(TAP_SLOT + p), true, alice);
        }
        assertEq(_rungAt(TAP_EVENT_SLOT, pool, RARE_PEAK), 800_000 ether, "six victories paid other than 80%");
        assertEq(_rungAt(TAP_EVENT_SLOT, pool, COMMON_PEAK), 400_000 ether, "six victories paid other than 40%");
    }

    /// @dev RESOLUTION-TIME STATE. Settlement is permissionless once the words are public, so the
    ///      ORDER windows are cranked in is a caller's choice — and the rule is read at the moment
    ///      the event resolves. An event cranked ahead of the routine victory does not double, and
    ///      the victory landing afterwards does not reach back.
    function test_anEventResolvedBeforeItsRoutineVictoryDoesNotDouble() public {
        uint256 pool = 1_000_000 ether;
        assertEq(_rungAt(TAP_EVENT_SLOT, pool, RARE_PEAK), 400_000 ether, "an unqualified event doubled");
        craps.noteRoutineVictory(TAP_SLOT, true, alice);
        assertEq(craps.progressivePool(), pool - 400_000 ether, "the later victory moved the settled pool");
    }

    /// @dev THE DOUBLED RUNG IS STILL RATIONED. The double chooses the CANDIDATE; the standing
    ///      curve then applies to it exactly as it does to an undoubled one, and what the curve
    ///      denies never leaves the pool.
    function test_aDoubledRungIsStillRationedByStanding() public {
        uint256 pool = 1_000_000 ether;
        craps.noteRoutineVictory(TAP_SLOT, true, alice);
        craps.seedProgressive(pool);

        uint256 candidate = 800_000 ether; // 80%, the doubled rare event rung
        uint256 credited = craps.awardAt(TAP_EVENT_SLOT, TAP_BANKROLL, true, RARE_PEAK, 6, alice);
        assertEq(credited, craps.boostShareOf(candidate, 6), "the doubled rung ignored the standing curve");
        assertLt(credited, candidate, "the fixture's standing denied nothing");
        assertEq(craps.progressivePool(), pool - credited, "the pool fell by other than the credit");
    }

    /// @dev A CUSTOM BATTLE IS OUTSIDE THE WHOLE SCHEDULE, and its slot arithmetic must not be
    ///      read as a period. Custom slots begin at a multiple of eight, so one of them lands on
    ///      the remainder the day's EVENT uses — and it still pays nothing and stamps nobody.
    function test_aCustomSlotOnTheEventsRemainderIsStillOutside() public {
        uint256 pool = 1_000_000 ether;
        uint64 customEventLike = uint64(craps.customSlotBase() + 7);
        assertEq(customEventLike % 8, 7, "the fixture is not on the event's remainder");

        craps.seedProgressive(pool);
        assertEq(
            craps.awardAt(customEventLike, TAP_BANKROLL, true, RARE_PEAK, craps.SYBIL_SCORE_FLOOR(), alice),
            0,
            "a custom battle drew on the pool"
        );
        assertEq(craps.progressivePool(), pool, "a custom battle moved the pool");

        // And `_payout` never offers a custom field to the write at all — it is behind the same
        // `scheduled` gate — so nothing a custom battle does can qualify a day.
        assertEq(craps.routineGoalDayOf(alice), 0, "a custom battle stamped a day");
    }

    /// @dev EVERY RUNG IS A FLOORED SHARE AND THE POOL IS CONSERVED, at every rung of the
    ///      schedule and for any pool. The award is `floor(pool * bps / 10_000)` exactly, it never
    ///      exceeds the pool, and the pool falls by exactly what was credited — which is what
    ///      makes the 80% rung safe to compute without a wide multiplication.
    function testFuzz_everyRungIsAFlooredShareAndConservesThePool(uint96 pool, uint8 pick) public {
        uint64[2] memory slots = [TAP_SLOT, TAP_EVENT_SLOT];
        uint64 slot = slots[pick % 2];
        bool rare = (pick >> 1) % 2 == 1;
        bool repeat = (pick >> 2) % 2 == 1;
        if (repeat) craps.noteRoutineVictory(TAP_SLOT, true, alice);

        uint256 bps = slot == TAP_EVENT_SLOT
            ? (rare ? craps.PROG_EVENT_RARE_BPS() : craps.PROG_EVENT_COMMON_BPS())
            : (rare ? craps.PROG_ROUTINE_RARE_BPS() : craps.PROG_ROUTINE_COMMON_BPS());
        if (repeat && slot == TAP_EVENT_SLOT) bps += bps;

        craps.seedProgressive(pool);
        uint256 credited =
            craps.awardAt(slot, TAP_BANKROLL, true, rare ? RARE_PEAK : COMMON_PEAK, craps.SYBIL_SCORE_FLOOR(), alice);

        assertEq(credited, craps.poolShareOf(pool, bps), "the rung is not the floored share of the pool");
        assertEq(credited, (uint256(pool) * bps) / craps.BPS_DENOMINATOR(), "the safe form is not the plain one");
        assertLe(credited, pool, "the award overdrew the pool");
        assertEq(craps.progressivePool(), uint256(pool) - credited, "the pool fell by other than the credit");
    }

    /// @dev END TO END, THROUGH A REAL FINALIZATION. Everything above taps the gate directly; this
    ///      proves `_payout` is actually WIRED to it, that the day it stamps is the field's own,
    ///      and — the rule most easily lost — that reaching Goal BEHIND the winner qualifies
    ///      nobody. Winning the main bounty is the whole qualification.
    ///
    ///      Sweeps settlement words until it has a field in which somebody other than the winner
    ///      also finished Goal, so the runner-up case is actually exercised rather than assumed.
    ///      Every word it touches is held to the full claim on the way past.
    function test_aRealRoutineFinalizationStampsItsWinnerAndNobodyElse() public {
        _freshDay();
        uint24 day = craps.currentDayIndex();
        address[3] memory field = [alice, bob, carol];
        for (uint256 i = 0; i < 3; ++i) _seat(field[i], PER, uint16(4 + i));

        uint64 slot = _slotAt(PER);
        bytes32 key = _keyOf(PER);
        _warpPastClose(PER);
        uint48 index = _armAt(PER);

        bool sawRunnerUpGoal;
        uint256 snap = vm.snapshotState();
        for (uint256 i = 0; i < 128 && !sawRunnerUpGoal; ++i) {
            _setWord(index, uint256(keccak256(abi.encode("stamp", i))));
            craps.resolveSlot(slot, WHOLE_FIELD);
            address won = craps.betOf(_idAt(slot, craps.battleOf(key).winnerId)).player;

            for (uint256 n = 0; n < 3; ++n) {
                uint256 id = _idAt(slot, uint64(n + 1));
                bool goal = craps.settlementIn(id, slot).stop == Craps.SlipStop.Goal;
                if (field[n] == won) {
                    // THE WINNER, and only where it finished Goal: the day, stored plus one.
                    assertEq(
                        craps.routineGoalDayOf(field[n]),
                        goal ? uint256(day) + 1 : 0,
                        "the winner's stamp is not its field's own day"
                    );
                } else {
                    assertEq(craps.routineGoalDayOf(field[n]), 0, "a seat that did not win the field was stamped");
                    if (goal) sawRunnerUpGoal = true;
                }
            }
            if (!sawRunnerUpGoal) {
                vm.revertToState(snap);
                snap = vm.snapshotState();
            }
        }
        assertTrue(sawRunnerUpGoal, "no word produced a Goal behind the winner: the runner-up rule is untested");
    }

    /// @dev THE WHOLE LOOP, on one real day: a routine window is finalized for real, its winner's
    ///      stamp is written by `_payout`, and THAT DAY'S OWN EVENT SLOT then reads it and doubles.
    ///      The tests above hold the write and the read apart; this is the one that proves the
    ///      figure the write leaves is the figure the read consumes.
    function test_aRealRoutineVictoryDoublesItsOwnDaysEvent() public {
        _freshDay();
        uint24 day = craps.currentDayIndex();
        _seat(alice, PER, 4);
        uint64 slot = _slotAt(PER);
        bytes32 key = _keyOf(PER);
        _warpPastClose(PER);
        uint48 index = _armAt(PER);

        // A word on which ALICE takes the field as Goal. Both halves matter: a bust would not
        // stamp, and another winner would stamp somebody else.
        bool armed;
        uint256 snap = vm.snapshotState();
        for (uint256 i = 0; i < 256 && !armed; ++i) {
            _setWord(index, uint256(keccak256(abi.encode("loop", i))));
            craps.resolveSlot(slot, WHOLE_FIELD);
            uint256 winnerId = _idAt(slot, craps.battleOf(key).winnerId);
            armed = craps.betOf(winnerId).player == alice
                && craps.settlementIn(winnerId, slot).stop == Craps.SlipStop.Goal;
            if (!armed) {
                vm.revertToState(snap);
                snap = vm.snapshotState();
            }
        }
        assertTrue(armed, "no word gave alice a routine Goal victory");
        assertEq(craps.routineGoalDayOf(alice), uint256(day) + 1, "the real finalization did not stamp the day");

        // THIS DAY'S OWN EVENT, at the slot the schedule puts it: `day * 8 + 7`.
        uint64 eventSlot = uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + craps.BONUS_PERIODS_PER_DAY());
        assertEq(eventSlot % craps.BONUS_SLOTS_PER_DAY(), 7, "the event slot is not on the event's remainder");

        uint256 pool = 1_000_000 ether;
        craps.seedProgressive(pool);
        assertEq(
            craps.awardAt(eventSlot, TAP_BANKROLL, true, RARE_PEAK, craps.SYBIL_SCORE_FLOOR(), alice),
            800_000 ether,
            "the day's event did not double off its own routine victory"
        );

        // And the NEXT day's event, which the same stamp cannot reach.
        craps.seedProgressive(pool);
        uint64 tomorrowEvent = eventSlot + uint64(craps.BONUS_SLOTS_PER_DAY());
        assertEq(
            craps.awardAt(tomorrowEvent, TAP_BANKROLL, true, RARE_PEAK, craps.SYBIL_SCORE_FLOOR(), alice),
            400_000 ether,
            "yesterday's victory doubled tomorrow's event"
        );
    }

    // ════════════════════════════════════════════════════════════════════════
    // C. THE STANDING CURVE — what it denies goes into the pool, once.
    // ════════════════════════════════════════════════════════════════════════

    /// @dev A RATIONED AWARD SUBTRACTS ONLY THE CREDIT. The candidate was already in the pool, so
    ///      what the standing denies never left it and is not added back a second time.
    function test_aRationedAwardSubtractsOnlyTheCredit() public {
        uint16[5] memory scores = [uint16(0), 1, 6, 11, 12];
        for (uint256 i = 0; i < 5; ++i) {
            uint256 pool = 900_000 ether;
            craps.seedProgressive(pool);
            uint256 candidate = craps.poolShareOf(pool, craps.PROG_ROUTINE_COMMON_BPS());
            uint256 expected = craps.boostShareOf(candidate, scores[i]);
            uint256 credited = craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, TAP_BANKROLL * 25, scores[i], alice);
            assertEq(credited, expected, "the award did not follow the standing curve");
            assertEq(craps.progressivePool(), pool - expected, "the pool fell by other than the credit");
        }

        // The worked example the specification states, in its own terms.
        craps.seedProgressive(900_000 ether);
        assertEq(
            craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, TAP_BANKROLL * 25, 6, alice),
            7_500 ether,
            "the score-6 credit is not 7,500"
        );
        assertEq(craps.progressivePool(), 892_500 ether, "the score-6 pool is not 892,500");
    }

    /// @dev AT FULL STANDING THERE IS NO RETENTION AND NO ROLLOVER — on the award and on the
    ///      ladder alike. Every forfeiture path is silent for a score at the floor.
    function test_fullStandingCreatesNoRetentionAnywhere() public {
        uint256 pool = 1_000_000 ether;
        craps.seedProgressive(pool);
        vm.recordLogs();
        uint256 credited = craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, TAP_BANKROLL * 25, craps.SYBIL_SCORE_FLOOR(), alice);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(
            credited,
            craps.poolShareOf(pool, craps.PROG_ROUTINE_COMMON_BPS()),
            "a full-standing winner did not take the whole candidate"
        );
        for (uint256 i = 0; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != _ROLLED_SIG, "a full-standing award still rolled money over");
        }
    }

    /// @dev THE PAYOUT LOG RECONCILES: old balance, rung, candidate, credit, retention, new
    ///      balance — all six recoverable from one event and the curve.
    function test_theAwardLogReconstructsTheWholeTransaction() public {
        uint256 pool = 900_000 ether;
        craps.seedProgressive(pool);
        vm.recordLogs();
        craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, TAP_BANKROLL * 25, 6, alice);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool seen;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] != _PAID_SIG) continue;
            assertEq(address(uint160(uint256(logs[i].topics[3]))), alice, "the award named another player");
            (
                bool rare,
                uint16 poolBps,
                uint256 peak,
                uint256 scoreBps,
                uint256 candidate,
                uint256 paid,
                uint256 balance
            ) = abi.decode(logs[i].data, (bool, uint16, uint256, uint256, uint256, uint256, uint256));
            assertFalse(rare, "a 25x high point is not rare");
            assertEq(poolBps, craps.PROG_ROUTINE_COMMON_BPS(), "the routine common rung is not 5%");
            assertEq(peak, TAP_BANKROLL * 25, "the log carried another high point");
            assertEq(scoreBps, 25 * craps.BPS_DENOMINATOR(), "the log carried another multiple");
            assertEq(candidate, pool / 20, "the candidate is not the routine common rung");
            assertEq(paid, candidate / 6, "the credit is not the score-6 share");
            // What the standing denied has no field of its own — it is `candidate - paid`, and it
            // never left the pool, which is what the balance below states.
            assertEq(balance + paid, pool, "the new balance plus the credit is not the old balance");
            seen = true;
        }
        assertTrue(seen, "no award was logged");
    }

    /// @dev THE ROLLOVER LOG, driven directly: it lands once, it names its source, and the balance
    ///      it reports is the one the pool actually holds. A zero rollover writes and logs nothing.
    function test_aRolloverLandsOnceAndAZeroOneIsSilent() public {
        craps.seedProgressive(1000 ether);
        vm.recordLogs();
        craps.rollIn(bytes32(uint256(1)), 1, 0);
        assertEq(vm.getRecordedLogs().length, 0, "a zero rollover was logged");
        assertEq(craps.progressivePool(), 1000 ether, "a zero rollover moved the pool");

        vm.recordLogs();
        craps.rollIn(bytes32(uint256(1)), 2, 400 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "a rollover logged other than once");
        assertEq(uint256(logs[0].topics[2]), 2, "the rollover did not name its source");
        (uint256 amount, uint256 balance) = abi.decode(logs[0].data, (uint256, uint256));
        assertEq(amount, 400 ether, "the rollover logged another amount");
        assertEq(balance, 1400 ether, "the rollover logged another balance");
        assertEq(craps.progressivePool(), balance, "the pool disagrees with its own log");
    }

    // ════════════════════════════════════════════════════════════════════════
    // D. THE LADDER AND THE LANE — a real field, a real rationed subsidy.
    // ════════════════════════════════════════════════════════════════════════

    /// @dev THE MAIN LADDER'S FORFEITURE, end to end and at every score the curve names. What the
    ///      winner is credited plus what the pool takes is the FULL-STANDING award exactly, at the
    ///      rounding stage the payment lands on.
    ///
    ///      THE TWO PROTOCOL BODIES ALWAYS HOLD THE FLOOR — `_seatBody` writes
    ///      `_SYBIL_SCORE_FLOOR` outright rather than reading an activity score — so a field they
    ///      win rolls nothing over and says nothing about the curve. The fixture therefore
    ///      searches the settling word for a table the PLAYER wins, replaying off a snapshot so
    ///      the search uses production's own comparator rather than a copy of it.
    function test_theMainLaddersForfeitureLandsInThePoolAtEveryScore() public {
        uint16[5] memory scores = [uint16(0), 1, 6, 11, 12];
        uint256 sawARollover;
        for (uint256 s = 0; s < 5; ++s) {
            _freshDay();
            uint256 poolBefore = craps.progressivePool();
            _seat(alice, PER, scores[s]);
            _warpPastClose(PER);
            uint48 index = _armAt(PER);
            uint64 slot = _slotAt(PER);
            bytes32 key = craps.keyOfSlot(slot);

            uint256 boost;
            uint256 rolled;
            bool found;
            uint256 snap = vm.snapshotState();
            for (uint256 i = 0; i < 96 && !found; ++i) {
                _setWord(index, uint256(keccak256(abi.encode("ladder", s, i))));
                boost = craps.boostUnitsAt(slot);
                if (boost == 0) continue;
                vm.recordLogs();
                craps.resolveSlot(slot, WHOLE_FIELD);
                if (craps.betOf(_idAt(slot, craps.battleOf(key).winnerId)).player == alice) {
                    rolled = _rolledIn(vm.getRecordedLogs(), 1);
                    found = true;
                } else {
                    vm.revertToState(snap);
                    snap = vm.snapshotState();
                }
            }
            assertTrue(found, "no word gave the player a boosted win: the fixture proves nothing");

            uint256 full = craps.roundBoostFor(boost);
            uint256 admitted = craps.roundBoostFor(craps.boostShareOf(boost, scores[s]));

            // THE IDENTITY: admitted + rolled == the full-standing award, in granules and so in
            // wei. It closes at the floor (nothing rolled) and at zero (everything did).
            assertEq(
                admitted + rolled / craps.BATTLE_STAKE_UNIT(), full, "credit plus rollover is not the full award"
            );
            assertEq(rolled, (full - admitted) * craps.BATTLE_STAKE_UNIT(), "the rollover is not what standing denied");
            assertGe(craps.progressivePool(), poolBefore, "a rollover took money out of the pool");
            if (admitted < full) {
                assertGt(rolled, 0, "the curve denied part of the award and nothing was banked");
                ++sawARollover;
            } else {
                // The floor, and the rung just under it: `_boostShare` divides by `12 - held`, so
                // a score of 11 takes the whole award exactly as a score of 12 does.
                assertEq(rolled, 0, "an award the curve admitted whole still rolled money over");
            }
            if (scores[s] >= craps.SYBIL_SCORE_FLOOR() - 1) {
                assertEq(admitted, full, "a score at or one below the floor was rationed");
            }
        }
        assertEq(sawARollover, 3, "the three rationed scores did not each bank a forfeiture");
    }

    /// @dev A SOLE HIGH RIDER'S DENIED CAPITAL NEVER GETS ON THE TABLE. It is banked before the
    ///      run is consulted, so nothing here manufactures a return on money the standing refused —
    ///      and only the admitted capital rides.
    function test_aSoleHighRidersDeniedCapitalIsBankedNotRidden() public {
        _freshDayWithHighAction();
        uint64 slot = _slotAt(PER);
        uint256 laneUnits;

        // A scoreless high roller: the whole lane boost is denied.
        _seatHigh(alice, PER, 0);
        _warpPastClose(PER);
        uint48 index = _armAt(PER);
        for (uint256 i = 0; i < 512; ++i) {
            _setWord(index, uint256(keccak256(abi.encode("sole", i))));
            laneUnits = craps.highBoostUnitsOf(slot, craps.wordAt(index));
            if (laneUnits > 0) break;
        }
        assertGt(laneUnits, 0, "the day funded no high lane: the fixture proves nothing");

        uint256 poolBefore = craps.progressivePool();
        vm.recordLogs();
        craps.resolveSlot(slot, WHOLE_FIELD);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 rolled = _rolledIn(logs, 3);
        assertEq(
            rolled,
            craps.roundBoostFor(laneUnits) * craps.BATTLE_STAKE_UNIT(),
            "a scoreless sole rider did not bank its whole lane boost"
        );
        // The same scoreless seat also wins the main field, so its LADDER forfeiture lands here
        // too. The pool's movement is the sum of every source and nothing besides.
        assertEq(
            craps.progressivePool(),
            poolBefore + rolled + _rolledIn(logs, 1) + _rolledIn(logs, 2),
            "the pool moved by other than its logged rollovers"
        );

        // And what rode home carries NO boost: with the boost denied, the rider's return is a
        // fraction of its extra bounties alone.
        PaidOut[] memory rides = _lanePaymentsIn(logs, true);
        assertEq(rides.length, 1, "the sole lane did not settle exactly once");
        CrapsBattle.Settlement memory s = craps.settlementIn(rides[0].betId, slot);
        uint256 extra =
            (craps.highMultOfSlot(slot) - 1) * craps.battleOf(craps.keyOfSlot(slot)).battleStake;
        (uint128 bank,,,,,) = craps.bonusTermsFor(craps.currentDayIndex(), PER);
        assertEq(rides[0].amount, craps.rideOf(s.paid, extra, bank), "the denied boost still rode");
    }

    /// @dev A CONTESTED LANE ROUTES ITS BOOST FORFEITURE AND NOTHING ELSE. The lane's principal is
    ///      player-funded — every seat posted the same bounties — so it pays out whole whatever
    ///      the winner's score, and no part of it reaches the pool.
    function test_aContestedLaneRoutesOnlyItsBoostForfeiture() public {
        _freshDayWithHighAction();
        uint64 slot = _slotAt(PER);
        _seatHigh(alice, PER, 0);
        _seatHigh(bob, PER, 0);
        _warpPastClose(PER);
        uint48 index = _armAt(PER);
        uint256 laneUnits;
        for (uint256 i = 0; i < 512; ++i) {
            _setWord(index, uint256(keccak256(abi.encode("contested", i))));
            laneUnits = craps.highBoostUnitsOf(slot, craps.wordAt(index));
            if (laneUnits > 0) break;
        }
        assertGt(laneUnits, 0, "the day funded no high lane: the fixture proves nothing");

        (uint32 heads,,,,) = craps.highFieldOf(craps.keyOfSlot(slot));
        assertEq(heads, 2, "the lane is not contested");
        uint256 principal = uint256(heads) * (craps.highMultOfSlot(slot) - 1)
            * craps.battleOf(craps.keyOfSlot(slot)).battleStake;

        uint256 poolBefore = craps.progressivePool();
        vm.recordLogs();
        craps.resolveSlot(slot, WHOLE_FIELD);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(
            _rolledIn(logs, 2),
            craps.roundBoostFor(laneUnits) * craps.BATTLE_STAKE_UNIT(),
            "the contested lane did not bank its denied boost"
        );
        PaidOut[] memory lane = _lanePaymentsIn(logs, false);
        assertEq(lane.length, 1, "a contested lane did not pay exactly once");
        assertEq(lane[0].amount, principal, "the lane paid other than its whole player-funded principal");
        assertEq(
            craps.progressivePool() - poolBefore,
            _rolledIn(logs, 1) + _rolledIn(logs, 2) + _rolledIn(logs, 3),
            "the pool moved by other than its logged rollovers"
        );
    }

    // ════════════════════════════════════════════════════════════════════════
    // E. THE ROLL COUNT — how it reaches the scoreboard, and what it does not touch.
    // ════════════════════════════════════════════════════════════════════════

    /// @dev EVERY SCHEDULED PRESET DIVIDES EXACTLY. The depth and the one target stay fixed at
    ///      every window of every day the schedule can draw.
    function test_everyScheduledPresetIsFiveDeepAtFiveX() public {
        uint256 periods = craps.BONUS_PERIODS_PER_DAY();
        for (uint24 d = 1; d <= 300; ++d) {
            _setDailyWord(d, uint256(keccak256(abi.encode("presets", d))));
            for (uint256 p = 0; p < periods; ++p) {
                (uint128 bank, uint128 goal,,,,) = craps.bonusTermsFor(d, p);
                // THE ROUND, not the seven chips an entrant posts: `bonusTermsFor` quotes the
                // posted stack, and the depth is against the whole ten-chip round.
                uint256 round = craps.roundOf(uint64(uint256(d) * craps.BONUS_SLOTS_PER_DAY() + p + 1));
                assertGt(round, 0, "a scheduled window plays a zero round");
                assertEq(uint256(bank) % round, 0, "a scheduled bankroll is not a whole number of rounds");
                assertEq(uint256(goal) % uint256(bank), 0, "a scheduled goal is not a whole multiple of its bankroll");
                assertEq(uint256(bank) / round, craps.SCHED_BANK_MULT(), "a scheduled depth is not five rounds");
                uint256 mult = uint256(goal) / uint256(bank);
                assertEq(mult, craps.SCHED_GOAL(), "a scheduled target is not 5x");
                // EVERY CUTOFF LANDS ON A WHOLE FLIP. The award compares whole-FLIP figures, so a
                // format whose cutoff fell between two of them would be judged on a floor.
                (uint256 c, uint256 r) = craps.progressiveThresholds();
                assertEq((uint256(bank) * c) % 1 ether, 0, "a common cutoff is not a whole number of FLIP");
                assertEq((uint256(bank) * r) % 1 ether, 0, "a rare cutoff is not a whole number of FLIP");
            }
        }
    }

    /// @dev THE SCOREBOARD ROUND-TRIPS EVERY HIGH POINT THE COMPOSITE CAN HOLD, up to and past
    ///      anything a scheduled table can produce, and the seat packed above it is never
    ///      disturbed. This is what the reclaimed roll slice paid for.
    function test_everyHighPointRoundTripsBesideItsSeat() public {
        (, uint256 primaryMask) = craps.winnerRegionShift();
        assertGt(primaryMask, 60_000 * 300, "the primary field cannot hold a maximal scheduled run");

        uint256[8] memory probe = [uint256(0), 1, 300, 60_000, 1_000_000, 1e9, 1e12, primaryMask];
        for (uint256 i = 0; i < 8; ++i) {
            bytes32 key = keccak256(abi.encode("peaks", i));
            craps.writeBattleWord(key, 2); // two entrants, so the fold cannot finalize and pay
            craps.scoreAt(key, craps.goalScore(probe[i], 0, 0), uint64(i + 1), 0, TAP_SLOT);
            // Read off the LIVE fold, not the finalized view: the field is still open, which is
            // exactly the state in which a displacement has to keep the two slices apart.
            assertEq(craps.leaderPeakOf(key), probe[i], "a high point did not round-trip");
            assertEq(craps.battleOf(key).winnerId, i + 1, "the seat above it moved");
        }

        // A 32-bit seat, at the top of its own range, still reads back whole beside a high point.
        bytes32 wide = keccak256("wide");
        craps.writeBattleWord(wide, 2);
        craps.scoreAt(wide, craps.goalScore(123_456, 0, 0), type(uint32).max, 0, TAP_SLOT);
        assertEq(craps.battleOf(wide).winnerId, type(uint32).max, "a full-width seat was truncated");
        assertEq(craps.leaderPeakOf(wide), 123_456, "the high point beside a full-width seat moved");
    }

    /// @dev A LARGE HIGH POINT IS NEVER WRAPPED INTO A SMALL SCORE. The money components SATURATE
    ///      at the field rather than masking into it, so a figure past the horizon still ranks at
    ///      the top of the ladder instead of at the bottom of it.
    function test_anEnormousHighPointSaturatesRatherThanWrapping() public {
        (, uint256 primaryMask) = craps.winnerRegionShift();
        uint256 saturating = craps.goalScore(primaryMask + 1_000_000, 0, 0);
        uint256 ordinary = craps.goalScore(60_000 * 300, 0, 0);
        assertGt(saturating, ordinary, "a wrapped high point ranked below an ordinary one");
        assertEq(
            (saturating >> 60) & primaryMask, primaryMask, "the saturating figure did not land on the field's ceiling"
        );
    }

    /// @dev THE HIGH POINT FOLLOWS THE LEAD AND NOTHING ELSE. A challenger that wins takes its own
    ///      figure with it; one that loses leaves the board exactly where it was.
    function test_theHighPointMovesWithTheLeaderAndOnlyWithIt() public {
        bytes32 key = keccak256("lead");
        craps.writeBattleWord(key, 5); // five entrants, so nothing finalizes mid-test
        uint256 low = craps.bustScore(3, 10, 12);
        uint256 high = craps.goalScore(4321, 10, 12);

        craps.scoreAt(key, low, 1, 0, TAP_SLOT);
        assertEq(craps.battleOf(key).winnerId, 1, "the first entrant did not lead unopposed");
        assertEq(craps.leaderPeakOf(key), 3, "a bust's primary is not its shooter count");

        // A LOSING challenger moves neither.
        craps.scoreAt(key, low - 1, 2, 0, TAP_SLOT);
        assertEq(craps.battleOf(key).winnerId, 1, "a losing challenger took the lead");
        assertEq(craps.leaderPeakOf(key), 3, "a losing challenger overwrote the board");

        // A WINNING one takes both.
        craps.scoreAt(key, high, 3, 0, TAP_SLOT);
        assertEq(craps.battleOf(key).winnerId, 3, "the displacing entrant did not take the lead");
        assertEq(craps.leaderPeakOf(key), 4321, "the displaced leader's primary was left behind");
    }

    /// @dev THE COMPARATOR IS THE HIGH POINT NOW, and a goal still beats every bust. A goal that
    ///      got further wins even though it took longer; a bust with an enormous remainder loses
    ///      to any goal at all.
    function test_theHigherGoalWinsAndEveryBustLosesToIt() public {
        bytes32 key = keccak256("rank");
        craps.writeBattleWord(key, 5);
        uint256 far = craps.goalScore(90_000, 100, 12);
        uint256 near = craps.goalScore(15_000, 100, 12);
        assertGt(far, near, "a higher high point does not outrank a lower one");

        craps.scoreAt(key, near, 1, 0, TAP_SLOT);
        craps.scoreAt(key, far, 2, 0, TAP_SLOT);
        assertEq(craps.battleOf(key).winnerId, 2, "the higher high point did not take the lead");

        // A BUST with an enormous remainder still loses to any goal.
        craps.scoreAt(key, craps.bustScore(511, 1e12, 12), 3, 0, TAP_SLOT);
        assertEq(craps.battleOf(key).winnerId, 2, "a rich bust outranked a goal");
    }

    /// @dev THE ENDING BANKROLL BREAKS A LEVEL HIGH POINT, and the standing breaks a level pair.
    ///      The ladder is exactly the one the comparator documents.
    function test_theComparatorLadderIsPeakThenEndingThenStanding() public view {
        assertGt(craps.goalScore(5000, 100, 0), craps.goalScore(4999, 1e12, 4095), "the peak is not the first term");
        assertGt(craps.goalScore(5000, 101, 0), craps.goalScore(5000, 100, 4095), "the ending is not the second term");
        assertGt(craps.goalScore(5000, 100, 7), craps.goalScore(5000, 100, 6), "the standing is not the last term");
    }

    /// @dev THE COMPOSITE DECODES BACK TO WHAT IT SAYS, and it says the same thing for both
    ///      products: a GOAL's primary is its high point and carries no shooter count, a BUST's
    ///      primary IS its shooter count and carries no high point.
    function test_theCompositeDecodesToTheFigureItHolds() public {
        Craps.SlipStop stop;
        uint256 hands;
        uint256 peak;
        uint256 end;

        (stop, hands, peak, end) = craps.decodeBest(craps.rawComposite(true, 7777, 1234, 12));
        assertEq(uint8(stop), uint8(Craps.SlipStop.Goal), "a goal did not decode as a goal");
        assertEq(peak, 7777, "a goal did not decode its high point");
        assertEq(end, 1234, "a goal did not decode its ending bankroll");
        assertEq(hands, 0, "a goal decoded a shooter count it never stored");

        (stop, hands, peak, end) = craps.decodeBest(craps.rawComposite(false, 41, 9, 12));
        assertEq(uint8(stop), uint8(Craps.SlipStop.Bust), "a bust did not decode as a bust");
        assertEq(hands, 41, "a bust did not decode its shooter count");
        assertEq(peak, 0, "a bust decoded a high point");
        assertEq(end, 9, "a bust did not decode its remainder");

        // And a real board reports the same through `battleOf`.
        bytes32 key = keccak256("stamped");
        craps.writeBattleWord(key, 1);
        craps.scoreAt(key, craps.goalScore(7777, 42, 3), 1, 0, TAP_SLOT);
        CrapsBattle.Battle memory b = craps.battleOf(key);
        assertTrue(b.finalized, "the one-seat field did not finalize");
        assertEq(b.winningPeak, 7777, "the board did not report its high point");
        assertEq(b.winningEnd, 42, "the board did not report its ending bankroll");
        assertEq(b.winningHands, 0, "a goal reported a shooter count");
    }

    /// @dev THE ENGINE'S OWN HIGH POINT REACHES THE SCOREBOARD. A real field, settled through the
    ///      shipped lane: the figure the board ends up holding is the WINNER's, taken from the
    ///      same `_settlementOf` the payment used, and it agrees with the finalized log.
    function test_theScoreboardHoldsTheWinnersOwnEngineHighPoint() public {
        _freshDay();
        _seat(alice, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _seat(bob, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _seat(carol, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _warpPastClose(PER);
        uint48 index = _armAt(PER);
        _setWord(index, uint256(keccak256("engine-peak")));

        uint64 slot = _slotAt(PER);
        bytes32 key = craps.keyOfSlot(slot);
        uint256 entrants = craps.battleOf(key).entrants;

        // Read every seat's high point BEFORE settling, off the shared settlement.
        uint256[] memory peaks = new uint256[](entrants + 1);
        uint256[] memory ends = new uint256[](entrants + 1);
        for (uint64 n = 1; n <= entrants; ++n) {
            CrapsBattle.Settlement memory st = craps.settlementIn(_idAt(slot, n), slot);
            peaks[n] = st.peak / 1 ether;
            ends[n] = st.won / 1 ether;
            assertGe(st.peak, st.won, "a run's high point sat below its ending bankroll");
        }

        vm.recordLogs();
        craps.resolveSlot(slot, WHOLE_FIELD);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        CrapsBattle.Battle memory done = craps.battleOf(key);
        assertTrue(done.finalized, "the field did not finalize");
        assertEq(done.winningEnd, ends[done.winnerId], "the board holds another seat's ending bankroll");
        if (done.winningStop == Craps.SlipStop.Goal) {
            assertEq(done.winningPeak, peaks[done.winnerId], "the board holds another seat's high point");
        }

        // And the finalized log agrees with the board on every figure it restates.
        (uint64 loggedWinner, uint256 loggedPeak, uint256 loggedEnd,) = _finalizedIn(logs, key);
        assertEq(loggedWinner, done.winnerId, "the log named another seat");
        assertEq(loggedPeak, done.winningPeak, "the log and the board disagree on the high point");
        assertEq(loggedEnd, done.winningEnd, "the log and the board disagree on the ending bankroll");
    }

    /// @dev THE HIGH POINT IS NEVER PAID. A qualified run is credited its ROUNDED ending-bankroll
    ///      payment — a post-goal losing shooter may have pulled the raw figure below the peak —
    ///      and never the mark it touched on the way.
    function test_theEndingBankrollIsPaidAndTheHighPointIsNot() public {
        _freshDay();
        _seat(alice, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _seat(bob, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _warpPastClose(PER);
        uint48 index = _armAt(PER);

        uint64 slot = _slotAt(PER);
        uint256 own = _ownSeatsOf(slot);
        uint256 sawGap;
        for (uint256 i = 0; i < 64 && sawGap == 0; ++i) {
            _setWord(index, uint256(keccak256(abi.encode("gap", i))));
            for (uint64 n = 1; n <= own; ++n) {
                CrapsBattle.Settlement memory st = craps.settlementIn(_idAt(slot, n), slot);
                if (st.stop != Craps.SlipStop.Goal || st.peak <= st.paid) continue;
                // The run's rounded payment stayed BELOW its own peak, and the preview quotes
                // that payment exactly. Round-to-nearest may sit above the raw ending bankroll.
                (, uint256 quoted) = craps.previewSettlement(_idAt(slot, n));
                assertEq(quoted, st.paid, "the preview did not quote the rounded ending payment");
                assertLt(quoted, st.peak, "a run was quoted its high point");
                ++sawGap;
            }
        }
        assertGt(sawGap, 0, "no word produced a goal that ended below its own high point");
    }

    // ════════════════════════════════════════════════════════════════════════
    // F. SETTLEMENT SAFETY — batching, order, reentry, and the books.
    // ════════════════════════════════════════════════════════════════════════

    /// @dev SPLIT BATCHES AND REPEATED CALLS PAY ONCE. The award lives in the one branch where the
    ///      last seat scores, and the cursor makes that branch unreachable a second time — so a
    ///      field cut into batches, and re-resolved afterwards, draws on the pool exactly once.
    function test_splitBatchesAndRepeatedResolutionPayOnce() public {
        _freshDay();
        _seat(alice, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _seat(bob, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _seat(carol, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _warpPastClose(PER);
        uint48 index = _armAt(PER);
        _setWord(index, uint256(keccak256("batched")));

        uint64 slot = _slotAt(PER);
        craps.seedProgressive(1_000_000 ether);
        // A cutoff of zero: every goal qualifies, so a double payment would be unmissable.
        // (The table's cutoffs are fixed, so the fixture instead reads what actually happened.)
        vm.recordLogs();
        craps.resolveSeats(slot, 1);
        craps.resolveSeats(slot, 1);
        craps.resolveSlot(slot, WHOLE_FIELD);
        craps.resolveSlot(slot, WHOLE_FIELD);
        craps.resolveSlot(slot, WHOLE_FIELD);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertTrue(craps.battleOf(craps.keyOfSlot(slot)).finalized, "the batched field did not finalize");
        bytes32 potSig = keccak256("CrapsBattlePaid(uint256,bytes32,address,uint256)");
        assertLe(_countSig(logs, potSig), 1, "the pot paid twice");
        assertLe(_countSig(logs, _PAID_SIG), 1, "the progressive paid twice");
        assertLe(_countSig(logs, _ROLLED_SIG), 3, "a rollover repeated");
    }

    /// @dev SETTLEMENT ORDER CANNOT CHANGE THE RECIPIENT OR THE AMOUNT. The same field, the same
    ///      word, cut two different ways: same winner, same high point, same pool movement.
    function test_settlementOrderChangesNeitherRecipientNorAmount() public {
        uint256[2] memory pool;
        uint64[2] memory winner;
        uint256[2] memory peak;

        // ONE field, one word, replayed. Building a second field would compare two different
        // races; the snapshot is what makes the batching the only thing that differs.
        _freshDay();
        _seat(alice, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _seat(bob, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _seat(carol, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _warpPastClose(PER);
        uint48 index = _armAt(PER);
        _setWord(index, uint256(keccak256("order-invariant")));
        uint64 slot = _slotAt(PER);
        craps.seedProgressive(1_000_000 ether);
        uint256 snap = vm.snapshotState();

        for (uint256 pass = 0; pass < 2; ++pass) {
            if (pass == 1) vm.revertToState(snap);
            if (pass == 0) {
                craps.resolveSlot(slot, WHOLE_FIELD);
            } else {
                // Every seat in its own transaction, the smallest batches the lane allows.
                craps.resolveSeats(slot, 16);
            }
            CrapsBattle.Battle memory b = craps.battleOf(craps.keyOfSlot(slot));
            assertTrue(b.finalized, "the field did not finalize");
            pool[pass] = craps.progressivePool();
            winner[pass] = b.winnerId;
            peak[pass] = b.winningPeak;
        }
        assertEq(winner[0], winner[1], "the batching chose a different winner");
        assertEq(peak[0], peak[1], "the batching stored a different high point");
        assertEq(pool[0], pool[1], "the batching moved the pool by a different amount");
    }

    /// @dev THE POOL IS REDUCED BEFORE THE CREDIT. Read back from inside the coinflip call itself:
    ///      a reentrant reader sees the post-payment balance, so no callback can be handed a pool
    ///      that still contains what is being paid out of it.
    function test_thePoolIsReducedBeforeTheExternalCredit() public {
        PoolWatcher watcher = new PoolWatcher(address(craps));
        vm.etch(ContractAddresses.COINFLIP, address(watcher).code);
        PoolWatcher(ContractAddresses.COINFLIP).arm(address(craps));

        craps.seedProgressive(1_000_000 ether);
        uint256 credited = craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, TAP_BANKROLL * 120, 12, alice);
        assertEq(credited, 100_000 ether, "the fixture did not draw the routine rare rung");
        assertEq(
            PoolWatcher(ContractAddresses.COINFLIP).seen(),
            900_000 ether,
            "the callee saw a pool that still held the award"
        );
        assertEq(craps.progressivePool(), 900_000 ether, "the pool did not settle on the post-payment balance");
    }

    /// @dev NONE OF THIS TOUCHES THE ACTION BOOKS. `_dayStaked` is bankroll handle and nothing
    ///      else: the day's contribution, every rollover and every award leave it exactly where a
    ///      field's bankrolls put it.
    function test_noProgressiveMoneyEverFeedsTheActionBooks() public {
        _freshDay();
        uint24 day = craps.currentDayIndex();
        uint256 staked = craps.dayStaked(day);
        uint256 highStaked = craps.highStakedOf(day);

        // Funding, a rollover and an award, all with the books held up against them.
        _openDay();
        craps.rollIn(bytes32(uint256(1)), 1, 777 ether);
        craps.seedProgressive(1_000_000 ether);
        craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, TAP_BANKROLL * 130, 12, alice);
        assertEq(craps.dayStaked(day), staked, "progressive money reached the day's action");
        assertEq(craps.highStakedOf(day), highStaked, "progressive money reached the high action");

        // And a real settled field books its BANKROLLS and nothing the pool did.
        _seat(alice, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _warpPastClose(PER);
        uint48 index = _armAt(PER);
        _setWord(index, uint256(keccak256("books")));
        uint64 slot = _slotAt(PER);
        uint256 entrants = craps.battleOf(craps.keyOfSlot(slot)).entrants;
        (uint128 bank,,,,,) = craps.bonusTermsFor(day, PER);
        uint256 before = craps.dayStaked(day);
        craps.resolveSlot(slot, WHOLE_FIELD);
        assertEq(
            craps.dayStaked(day) - before, uint256(bank) * entrants, "the field booked other than its bankrolls"
        );
    }

    /// @dev THE MAIN WINNER IS THE ONE THE COMPARATOR NAMED — the progressive does not choose, and
    ///      a high multiple does not scale what it pays.
    function test_theProgressiveNeitherChoosesTheWinnerNorScalesWithTheMultiple() public {
        uint256 pool = 1_000_000 ether;
        // The same qualifying result, at the ordinary seat and at a high one: identical award.
        craps.seedProgressive(pool);
        uint256 plain = craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, TAP_BANKROLL * 120, 12, alice);
        craps.seedProgressive(pool);
        // A high seat differs only in what it staked; the award reads the scoreboard alone.
        uint256 high = craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, TAP_BANKROLL * 120, 12, bob);
        assertEq(plain, high, "the award moved with the seat rather than with the scoreboard");

        // And a field whose main winner busts pays nobody, however the lane went.
        craps.seedProgressive(pool);
        assertEq(
            craps.awardAt(TAP_SLOT, TAP_BANKROLL, false, TAP_BANKROLL * 900, 12, carol),
            0,
            "a busted main winner was paid"
        );
        assertEq(craps.progressivePool(), pool, "a busted main winner moved the pool");
    }

    /// @dev THE HIGH LANE CANNOT CLAIM IT. The award is keyed to the MAIN scoreboard's winner and
    ///      to nothing else, so a field whose lane goes to a different seat still pays the
    ///      progressive — if it pays one at all — to the seat the main comparator named.
    function test_aHighLaneVictoryAloneCannotClaimTheProgressive() public {
        _freshDayWithHighAction();
        _seatHigh(alice, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _seatHigh(bob, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _seat(carol, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _warpPastClose(PER);
        uint48 index = _armAt(PER);
        uint64 slot = _slotAt(PER);
        bytes32 key = craps.keyOfSlot(slot);

        // Search for a table whose LANE winner is not its MAIN winner, so the two are actually
        // separable — otherwise the assertion below is satisfied by coincidence.
        bool split;
        uint256 snap = vm.snapshotState();
        Vm.Log[] memory logs;
        for (uint256 i = 0; i < 96 && !split; ++i) {
            _setWord(index, uint256(keccak256(abi.encode("lane-vs-main", i))));
            craps.seedProgressive(1_000_000 ether);
            vm.recordLogs();
            craps.resolveSlot(slot, WHOLE_FIELD);
            logs = vm.getRecordedLogs();
            PaidOut[] memory lane = _lanePaymentsIn(logs, false);
            if (lane.length == 1 && lane[0].betId != _idAt(slot, craps.battleOf(key).winnerId)) {
                split = true;
            } else {
                vm.revertToState(snap);
                snap = vm.snapshotState();
            }
        }
        assertTrue(split, "no word separated the lane winner from the main winner");

        uint256 mainId = _idAt(slot, craps.battleOf(key).winnerId);
        uint256 awards;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] != _PAID_SIG) continue;
            assertEq(uint256(logs[i].topics[1]), mainId, "the progressive named a seat the main board did not");
            ++awards;
        }
        // Whether this particular table qualified is the dice's business; that it never paid the
        // lane winner is not.
        assertLe(awards, 1, "one field paid more than one progressive award");
    }

    /// @dev THE POOL CANNOT BE OVERDRAWN, at any balance, any high point and any score. Integer
    ///      division floors, the curve only ever divides, and the pool falls by
    ///      exactly what was credited.
    function testFuzz_theAwardNeverOverdrawsAndTheBooksClose(uint96 pool, uint32 peakMult, uint8 standing) public {
        uint256 held = standing % 16;
        // A high point as a MULTIPLE of the tap's own bankroll, from nothing to far past the rare
        // cutoff — the range the award actually reads.
        uint256 m = bound(uint256(peakMult), 0, 4000);
        uint256 peakFlip = TAP_BANKROLL * m;
        craps.seedProgressive(pool);

        uint256 credited = craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, peakFlip, held, alice);
        assertLe(credited, pool, "the award overdrew the pool");
        assertEq(craps.progressivePool(), uint256(pool) - credited, "the pool fell by other than the credit");

        // And it is the RIGHT rung: rare overrides common, and below common nothing is paid.
        (uint256 c, uint256 r) = craps.progressiveThresholds();
        uint256 score = m * craps.BPS_DENOMINATOR();
        // TAP_SLOT is a ROUTINE window, so the two rungs are 10% and 5%.
        uint256 bps = score >= r
            ? craps.PROG_ROUTINE_RARE_BPS()
            : (score >= c ? craps.PROG_ROUTINE_COMMON_BPS() : 0);
        uint256 candidate = bps == 0 ? 0 : craps.poolShareOf(pool, bps);
        assertEq(credited, craps.boostShareOf(candidate, held), "the award is not the rung's standing share");
    }

    /// @dev THE WHOLE LEDGER CLOSES. Over a scripted run of days, rollovers and awards, funding
    ///      plus rollovers minus credits is the pool — reconstructed from the logs alone, which is
    ///      exactly what an indexer has.
    function test_theLogsReconstructThePoolFromGenesis() public {
        vm.recordLogs();
        for (uint256 i = 0; i < 4; ++i) {
            _freshDay();
            _seat(alice, PER, uint16(i % 12));
            _warpPastClose(PER);
            uint48 index = _armAt(PER);
            _setWord(index, uint256(keccak256(abi.encode("ledger", i))));
            craps.resolveSlot(_slotAt(PER), WHOLE_FIELD);
        }
        craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, TAP_BANKROLL * 130, 6, bob);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        int256 ledger;
        for (uint256 i = 0; i < logs.length; ++i) {
            bytes32 sig = logs[i].topics[0];
            if (sig == keccak256("CrapsProgressiveFunded(uint24,uint256,uint256)")) {
                (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
                ledger += int256(amount);
            } else if (sig == _ROLLED_SIG) {
                (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
                ledger += int256(amount);
            } else if (sig == _PAID_SIG) {
                (,,,,, uint256 paid,) = abi.decode(
                    logs[i].data, (bool, uint16, uint256, uint256, uint256, uint256, uint256)
                );
                ledger -= int256(paid);
            }
        }
        assertGt(ledger, 0, "the scripted run banked nothing at all");
        assertEq(uint256(ledger), craps.progressivePool(), "the logs do not reconstruct the pool");
    }

    /// @dev THE INDIVIDUAL RUN'S PREVIEW IS UNTOUCHED. The progressive is a field award decided at
    ///      finalization, so it is no part of what a single slip is quoted — and the quote still
    ///      matches the payment to the wei.
    function test_theRunPreviewStillMatchesThePaymentExactly() public {
        _freshDay();
        _seat(alice, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _seat(bob, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _warpPastClose(PER);
        uint48 index = _armAt(PER);
        _setWord(index, uint256(keccak256("preview")));

        uint64 slot = _slotAt(PER);
        // A DAY TICKET is stored at its day's reserved slot, which names no table index, so it has
        // no preview to compare — the window's own seats are what this grades.
        uint64 own = _ownSeatsOf(slot);
        assertGt(own, 0, "the window took no seats of its own");
        uint256[] memory quoted = new uint256[](own + 1);
        for (uint64 n = 1; n <= own; ++n) {
            (, quoted[n]) = craps.previewSettlement(_idAt(slot, n));
        }

        craps.seedProgressive(1_000_000 ether);
        vm.recordLogs();
        craps.resolveSlot(slot, WHOLE_FIELD);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 sig = keccak256("CrapsBetSettled(uint256,address,uint256,uint256)");
        uint256 checked;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] != sig) continue;
            (, uint256 paid) = abi.decode(logs[i].data, (uint256, uint256));
            uint256 betId = uint256(logs[i].topics[1]);
            for (uint64 n = 1; n <= own; ++n) {
                if (_idAt(slot, n) != betId) continue;
                assertEq(paid, quoted[n], "a run paid other than its preview");
                ++checked;
            }
        }
        assertEq(checked, own, "not every own seat's preview was graded");
    }

    /// @dev WHAT THE PROGRESSIVE COSTS, measured rather than argued. Three figures: the day that
    ///      funds it, a finalization that does not qualify, and one that does.
    ///
    ///      The qualifying path is the only one that spends anything beyond a branch, and it is
    ///      reached at most once per finalized field — never per entrant, and never on a seat that
    ///      is not the last to score.
    function test_whatTheProgressiveCosts() public {
        // ONE: the day that funds it. The pool's slot is cold on the first opened day and warm
        // ever after, so both are worth stating.
        vm.warp(_dayStart() + 1 days + _closeOf(PER - 1));
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
        uint256 g = gasleft();
        _openDay();
        emit log_named_uint("openBonusDay, pool slot COLD ", g - gasleft());

        vm.warp(_dayStart() + 1 days + _closeOf(PER - 1));
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
        g = gasleft();
        _openDay();
        emit log_named_uint("openBonusDay, pool slot warm ", g - gasleft());

        // TWO: a finalization that does not qualify — the branch every ordinary field takes.
        _seat(alice, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _seat(bob, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _warpPastClose(PER);
        uint48 index = _armAt(PER);
        _setWord(index, uint256(keccak256("cost")));
        uint64 slot = _slotAt(PER);
        uint256 entrants = craps.battleOf(craps.keyOfSlot(slot)).entrants;
        g = gasleft();
        craps.resolveSlot(slot, WHOLE_FIELD);
        uint256 whole = g - gasleft();
        emit log_named_uint("resolveSlot, whole field     ", whole);
        emit log_named_uint("  entrants                   ", entrants);
        emit log_named_uint("  per entrant                ", whole / entrants);

        // THREE: the qualifying award itself, on a pool that pays.
        craps.seedProgressive(1_000_000 ether);
        g = gasleft();
        craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, TAP_BANKROLL * 120, 12, alice);
        emit log_named_uint("a paying rare award          ", g - gasleft());

        craps.seedProgressive(1_000_000 ether);
        g = gasleft();
        craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, TAP_BANKROLL * 10, 12, alice);
        emit log_named_uint("a non-qualifying test        ", g - gasleft());

        // The settle walk stays far inside the batch ceiling the schedule is sized against.
        assertLt(whole, 2_250_000, "a whole field's settlement passed the engine's gas ceiling");
    }

    // ════════════════════════════════════════════════════════════════════════
    // Fixtures
    // ════════════════════════════════════════════════════════════════════════

    /// @dev The instant the protocol day now running opened.
    function _dayStart() internal view returns (uint256) {
        return block.timestamp - ((block.timestamp - 82_620) % 1 days);
    }

    /// @dev When `period` stops taking bets, measured from the day's start.
    function _closeOf(uint256 period) internal view returns (uint256) {
        if (period + 1 == craps.BONUS_PERIODS_PER_DAY()) return 1 days - craps.EVENT_LEAD();
        uint256 base = period == 0 ? craps.BONUS_EVENT_CLOSE() : period * craps.BONUS_PERIOD();
        return base + craps.BONUS_CLOCK_ALIGN();
    }

    function _warpPastClose(uint256 period) internal {
        vm.warp(_dayStart() + _closeOf(period));
    }

    function _armAt(uint256 period) internal returns (uint48 index) {
        (, uint48 already,,) = craps.bonusWindowOf(period);
        index = already == 0 ? craps.armBonusWindow(_slotAt(period)) : already;
    }

    /// @dev Move to a day nobody has opened, land inside the window under test, and open it.
    function _freshDay() internal {
        vm.warp(_dayStart() + 1 days + _closeOf(PER - 1));
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
        _openDay();
    }

    /// @dev The same, with a week of HIGH action behind it, so the day actually funds a high lane.
    function _freshDayWithHighAction() internal {
        vm.warp(_dayStart() + 10 days + _closeOf(PER - 1));
        uint24 today = craps.currentDayIndex();
        for (uint256 i = 1; i <= craps.BOOST_ACTION_WINDOW_DAYS(); ++i) {
            craps.bookHighDay(today - uint24(i), 40_000_000 ether);
        }
        _setDailyWord(today, PLAIN_WORD);
        _openDay();
    }

    /// @dev Seven chips, packed: three on the line, three on place-6 and one on place-8.
    uint32 internal constant SEVEN = 3 | (uint32(3) << 9) | (uint32(1) << 12);

    function _seat(address who, uint256 period, uint16 standing) internal returns (uint256) {
        game.setScore(who, standing);
        vm.prank(who);
        return craps.enterBonusBattle(period, SEVEN, 1);
    }

    function _seatHigh(address who, uint256 period, uint16 standing) internal returns (uint256) {
        game.setScore(who, standing);
        // The multiple is READ FIRST and held: an external call inside the argument list would
        // consume the prank below and seat the test contract instead of `who`.
        uint16 mult = uint16(craps.highMultOfSlot(_slotAt(period)));
        vm.prank(who);
        return craps.enterBonusBattle(period, SEVEN, mult);
    }

    /// @dev A seat's real bet id: a window's own seats first, then the day tail behind them.
    function _idAt(uint64 slot, uint64 n) internal view returns (uint256) {
        uint24 day = uint24(uint256(slot) / craps.BONUS_SLOTS_PER_DAY());
        uint64 dayN = uint32(craps.dayTicketsOf(day));
        uint64 ownN = uint64(craps.battleOf(craps.keyOfSlot(slot)).entrants) - dayN;
        return n <= ownN ? (uint256(slot) << 64) | n : (craps._daySlotOfPub(day) << 64) | (n - ownN);
    }

    /// @dev How many of a window's seats are its OWN — the field less the day tail behind it.
    function _ownSeatsOf(uint64 slot) internal view returns (uint64) {
        uint24 day = uint24(uint256(slot) / craps.BONUS_SLOTS_PER_DAY());
        return uint64(craps.battleOf(craps.keyOfSlot(slot)).entrants) - uint32(craps.dayTicketsOf(day));
    }

    /// @dev The award a pool of `pool` pays a full run at these terms, with the pool restored
    ///      afterwards so a sweep grades every cutoff against the same balance. `peakFlip` is a
    ///      whole-FLIP high point against `TAP_BANKROLL`.
    function _awardWith(uint256 pool, uint256 peakFlip, uint256 standing) internal returns (uint256) {
        craps.seedProgressive(pool);
        return craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, peakFlip, standing, alice);
    }

    /// @dev Every rollover of one source in a log stream, summed.
    function _rolledIn(Vm.Log[] memory logs, uint8 source) internal pure returns (uint256 total) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] != _ROLLED_SIG || uint256(logs[i].topics[2]) != source) continue;
            (uint256 amount,) = abi.decode(logs[i].data, (uint256, uint256));
            total += amount;
        }
    }

    function _countSig(Vm.Log[] memory logs, bytes32 sig) internal pure returns (uint256 n) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] == sig) ++n;
        }
    }

    /// @dev The finalized log for one battle key.
    function _finalizedIn(Vm.Log[] memory logs, bytes32 key)
        internal
        pure
        returns (uint64 winner, uint256 peak, uint256 end, uint256 scoreBps)
    {
        bytes32 sig = keccak256("CrapsBattleFinalized(bytes32,uint8,uint64,uint256,uint256,uint256,uint256)");
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] != sig || logs[i].topics[1] != key) continue;
            (, winner, peak, end, scoreBps,) =
                abi.decode(logs[i].data, (uint8, uint64, uint256, uint256, uint256, uint256));
            return (winner, peak, end, scoreBps);
        }
        revert("no finalization log for that battle");
    }

    // ════════════════════════════════════════════════════════════════════════
    // G. THE PASS SPLIT — half of each protocol award banks as passes, per source.
    // ════════════════════════════════════════════════════════════════════════

    bytes32 internal constant _SPLIT_SIG =
        keccak256("CrapsProtocolAwardSplit(bytes32,address,uint8,uint256,uint256)");

    /// @dev Every split a resolve announced for `source`: how many, and the summed gross/liquid.
    function _splitsIn(Vm.Log[] memory logs, uint8 source)
        internal
        pure
        returns (uint256 count, uint256 gross, uint256 liquid)
    {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] != _SPLIT_SIG || uint256(logs[i].topics[3]) != source) continue;
            (uint256 g, uint256 l) = abi.decode(logs[i].data, (uint256, uint256));
            ++count;
            gross += g;
            liquid += l;
        }
    }

    /// @dev The summed pass VALUE every split banked for `who`, whatever the source.
    function _splitValueTo(Vm.Log[] memory logs, address who) internal pure returns (uint256 total) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] != _SPLIT_SIG) continue;
            if (address(uint160(uint256(logs[i].topics[2]))) != who) continue;
            (uint256 g, uint256 l) = abi.decode(logs[i].data, (uint256, uint256));
            total += g - l;
        }
    }

    function _freshDayWithMainAction() internal {
        vm.warp(_dayStart() + 10 days + _closeOf(PER - 1));
        uint24 today = craps.currentDayIndex();
        for (uint256 i = 1; i <= craps.BOOST_ACTION_WINDOW_DAYS(); ++i) {
            craps.bookDay(today - uint24(i), 40_000_000 ether);
        }
        _setDailyWord(today, PLAIN_WORD);
        _openDay();
    }

    /// @dev THE PROGRESSIVE DEBITS GROSS AND PAYS LIQUID PLUS PASSES. The pool falls by the whole
    ///      standing-admitted award — a pass is that award paying in a different shape — while
    ///      the Coinflip credit is only the liquid remainder, and the two conserve the gross.
    function test_aProgressiveAwardDebitsGrossAndPaysLiquidPlusPasses() public {
        uint256 pool = 1_000_000 ether;
        craps.seedProgressive(pool);
        uint256 candidate = craps.poolShareOf(pool, craps.PROG_ROUTINE_COMMON_BPS());
        uint256 before = coinflip.staked(alice);
        vm.recordLogs();
        uint256 debited =
            craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, TAP_BANKROLL * 25, uint16(craps.SYBIL_SCORE_FLOOR()), alice);

        // PROG-01/02: the gross award and the pool debit are exactly what they always were.
        assertEq(debited, candidate, "the pool debit is not the gross standing-admitted award");
        assertEq(craps.progressivePool(), pool - candidate, "the pool retained the pass slice");

        // A 50,000 target halves to 25,000 — one normal pass, and the rest of the gross liquid.
        (uint256 n, uint256 h) = craps.passCreditsOf(alice);
        assertEq(n, 1, "the award did not bank its one normal pass");
        assertEq(h, 0, "a normal-denomination award banked a high");
        assertEq(
            coinflip.staked(alice) - before,
            candidate - craps.NORMAL_PASS_VALUE(),
            "the liquid credit is not the gross minus the pass value"
        );

        (uint256 count, uint256 g, uint256 l) = _splitsIn(vm.getRecordedLogs(), 4);
        assertEq(count, 1, "the progressive did not announce exactly one split");
        assertEq(g, candidate, "the split misstates the gross award");
        assertEq(l, candidate - craps.NORMAL_PASS_VALUE(), "the split misstates the liquid remainder");
    }

    /// @dev A HUGE PROGRESSIVE AWARD CAPS AT THIRTY HIGHS, and the cap deletes nothing: the pool
    ///      still falls by the whole gross, and everything the cap refused pays out liquid.
    function test_aHugeProgressiveAwardCapsAtThirtyHighs() public {
        uint256 pool = 600_000_000 ether;
        craps.seedProgressive(pool);
        uint256 candidate = craps.poolShareOf(pool, craps.PROG_ROUTINE_COMMON_BPS());
        uint256 before = coinflip.staked(alice);
        uint256 debited =
            craps.awardAt(TAP_SLOT, TAP_BANKROLL, true, TAP_BANKROLL * 25, uint16(craps.SYBIL_SCORE_FLOOR()), alice);

        assertEq(debited, candidate, "the pool debit is not the gross award");
        (uint256 n, uint256 h) = craps.passCreditsOf(alice);
        assertEq(n, 0, "a high-denomination award banked normals");
        assertEq(h, craps.MAX_HIGH_PASSES_PER_AWARD(), "the cap did not hold at thirty");
        assertEq(
            coinflip.staked(alice) - before,
            candidate - 30 * craps.HIGH_PASS_VALUE(),
            "the capped excess did not return as liquid FLIP"
        );
    }

    /// @dev A PUMPED MAIN BOOST SPLITS AND THE BOUNTIES STAY LIQUID. On a day whose action funds
    ///      a converting boost, the winner's pot is the bounties plus only the LIQUID part of the
    ///      admitted boost; the pass value banks beside it and the three conserve exactly.
    function test_aPumpedMainBoostSplitsAndTheBountiesStayLiquid() public {
        _freshDayWithMainAction();
        _seat(alice, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _warpPastClose(PER);
        uint48 index = _armAt(PER);
        uint64 slot = _slotAt(PER);
        bytes32 key = craps.keyOfSlot(slot);

        bool found;
        uint256 drew;
        Vm.Log[] memory logs;
        uint256 snap = vm.snapshotState();
        for (uint256 i = 0; i < 96 && !found; ++i) {
            _setWord(index, uint256(keccak256(abi.encode("mainsplit", i))));
            drew = craps.roundBoostFor(craps.boostUnitsAt(slot)) * craps.BATTLE_STAKE_UNIT();
            // A boost too small to convert proves nothing here; the boundary suite owns that case.
            if (drew < 2 * craps.NORMAL_PASS_VALUE()) continue;
            vm.recordLogs();
            craps.resolveSlot(slot, WHOLE_FIELD);
            if (craps.betOf(_idAt(slot, craps.battleOf(key).winnerId)).player == alice) {
                logs = vm.getRecordedLogs();
                found = true;
            } else {
                vm.revertToState(snap);
                snap = vm.snapshotState();
            }
        }
        assertTrue(found, "no word gave alice a converting boosted win: the fixture proves nothing");

        (uint256 count, uint256 g, uint256 l) = _splitsIn(logs, 1);
        assertEq(count, 1, "the main ladder did not announce exactly one split");
        assertEq(g, drew, "the split's gross is not the admitted boost");
        uint256 banked = g - l;
        assertGt(banked, 0, "a converting boost banked nothing");

        // The pot: every bounty whole, plus only the liquid part of the boost.
        CrapsBattle.Battle memory done = craps.battleOf(key);
        uint256 stakes = done.battleStake * done.entrants;
        PaidOut[] memory pots = _potsIn(logs);
        assertEq(pots.length, 1, "the field paid other than one pot");
        assertEq(pots[0].amount, stakes + drew - banked, "the pot is not bounties plus the liquid boost");

        // And the banked value is exactly the passes alice now holds.
        (uint256 n, uint256 h) = craps.passCreditsOf(alice);
        assertEq(
            n * craps.NORMAL_PASS_VALUE() + h * craps.HIGH_PASS_VALUE(),
            _splitValueTo(logs, alice),
            "the banked credits do not price back to the split value"
        );
    }

    /// @dev A SCORE-ZERO WINNER CONVERTS NOTHING even on a pumped day: the ration runs first, the
    ///      denied boost rolls into the progressive as it always did, and no pass rides what the
    ///      standing refused.
    function test_aScoreZeroWinnerBanksNoPassesOnAPumpedDay() public {
        _freshDayWithMainAction();
        _seat(alice, PER, 0);
        _warpPastClose(PER);
        uint48 index = _armAt(PER);
        uint64 slot = _slotAt(PER);
        bytes32 key = craps.keyOfSlot(slot);

        bool found;
        Vm.Log[] memory logs;
        uint256 snap = vm.snapshotState();
        for (uint256 i = 0; i < 96 && !found; ++i) {
            _setWord(index, uint256(keccak256(abi.encode("zerosplit", i))));
            if (craps.boostUnitsAt(slot) == 0) continue;
            vm.recordLogs();
            craps.resolveSlot(slot, WHOLE_FIELD);
            if (craps.betOf(_idAt(slot, craps.battleOf(key).winnerId)).player == alice) {
                logs = vm.getRecordedLogs();
                found = true;
            } else {
                vm.revertToState(snap);
                snap = vm.snapshotState();
            }
        }
        assertTrue(found, "no word gave the scoreless player a boosted win: the fixture proves nothing");

        (uint256 count,,) = _splitsIn(logs, 1);
        assertEq(count, 0, "a fully denied boost still split");
        (uint256 n, uint256 h) = craps.passCreditsOf(alice);
        assertEq(n + h, 0, "a scoreless winner banked passes");
        assertGt(_rolledIn(logs, 1), 0, "the denied boost no longer rolls into the pool");
    }

    /// @dev A SOLE RIDER'S PROTOCOL RIDE SPLITS AND THE BOUNTY RIDE STAYS WHOLE. The pass slice
    ///      is priced off the pro-rata copy the LANE BOOST alone earned; the extra bounties'
    ///      ride pays out liquid in full, and the combined-floor figure is preserved to the wei.
    function test_aSoleRidersProtocolRideSplitsAndTheBountyRideStaysWhole() public {
        _freshDayWithHighAction();
        uint64 slot = _slotAt(PER);
        _seatHigh(alice, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _warpPastClose(PER);
        uint48 index = _armAt(PER);

        bool found;
        uint256 lane;
        Vm.Log[] memory logs;
        uint256 snap = vm.snapshotState();
        for (uint256 i = 0; i < 256 && !found; ++i) {
            _setWord(index, uint256(keccak256(abi.encode("solesplit", i))));
            lane = craps.roundBoostFor(craps.highBoostUnitsOf(slot, craps.wordAt(index)))
                * craps.BATTLE_STAKE_UNIT();
            if (lane == 0) continue;
            vm.recordLogs();
            craps.resolveSlot(slot, WHOLE_FIELD);
            logs = vm.getRecordedLogs();
            // The claim needs a CONVERTING protocol ride — a run good enough that half its
            // lane-boost copy buys at least one pass.
            (uint256 c,,) = _splitsIn(logs, 3);
            if (c == 1) {
                found = true;
            } else {
                vm.revertToState(snap);
                snap = vm.snapshotState();
            }
        }
        assertTrue(found, "no word produced a converting sole ride: the fixture proves nothing");

        PaidOut[] memory rides = _lanePaymentsIn(logs, true);
        assertEq(rides.length, 1, "the sole lane did not settle exactly once");
        CrapsBattle.Settlement memory s = craps.settlementIn(rides[0].betId, slot);
        uint256 extra = (craps.highMultOfSlot(slot) - 1) * craps.battleOf(craps.keyOfSlot(slot)).battleStake;
        (uint128 bank,,,,,) = craps.bonusTermsFor(craps.currentDayIndex(), PER);

        // The combined floor first: what rode home plus the pass value is the WHOLE ride, the
        // same single-floor figure the seat was always owed.
        (, uint256 g, uint256 l) = _splitsIn(logs, 3);
        assertEq(g, craps.rideOf(s.paid, lane, bank), "the split's gross is not the protocol ride");
        assertEq(
            rides[0].amount + (g - l),
            craps.rideOf(s.paid, extra + lane, bank),
            "liquid ride plus pass value is not the combined-floor ride"
        );
        // And the bounty ride is untouched: the liquid payment covers it in full.
        assertGe(rides[0].amount, craps.rideOf(s.paid, extra, bank), "the pass slice ate into the bounty ride");
    }

    /// @dev A CONTESTED LANE SPLITS ONLY ITS BOOST. Every seat posted the same extra bounties and
    ///      that principal pays out whole and liquid; only the admitted protocol boost halves
    ///      into passes.
    function test_aContestedLanesBoostSplitsAndThePrincipalPaysWhole() public {
        _freshDayWithHighAction();
        uint64 slot = _slotAt(PER);
        _seatHigh(alice, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _seatHigh(bob, PER, uint16(craps.SYBIL_SCORE_FLOOR()));
        _warpPastClose(PER);
        uint48 index = _armAt(PER);

        uint256 lane;
        for (uint256 i = 0; i < 512; ++i) {
            _setWord(index, uint256(keccak256(abi.encode("contestedsplit", i))));
            lane = craps.roundBoostFor(craps.highBoostUnitsOf(slot, craps.wordAt(index)))
                * craps.BATTLE_STAKE_UNIT();
            if (lane >= 2 * craps.NORMAL_PASS_VALUE()) break;
        }
        assertGe(lane, 2 * craps.NORMAL_PASS_VALUE(), "the day funded no converting lane: the fixture proves nothing");

        (uint32 heads,,,,) = craps.highFieldOf(craps.keyOfSlot(slot));
        assertEq(heads, 2, "the lane is not contested");
        uint256 principal =
            uint256(heads) * (craps.highMultOfSlot(slot) - 1) * craps.battleOf(craps.keyOfSlot(slot)).battleStake;

        vm.recordLogs();
        craps.resolveSlot(slot, WHOLE_FIELD);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 count, uint256 g, uint256 l) = _splitsIn(logs, 2);
        assertEq(count, 1, "the contested lane did not announce exactly one split");
        assertEq(g, lane, "the split's gross is not the admitted lane boost");
        assertGt(g - l, 0, "a converting lane banked nothing");

        PaidOut[] memory paid = _lanePaymentsIn(logs, false);
        assertEq(paid.length, 1, "a contested lane did not pay exactly once");
        assertEq(paid[0].amount, principal + l, "the lane paid other than principal plus the liquid boost");
    }

    /// @dev A CUSTOM BATTLE NEVER SPLITS. It carries no house money, so there is no protocol
    ///      award to halve: the pot pays whole, no split is announced and no pass is banked.
    function test_aCustomBattleSplitsNothing() public {
        uint64 slot = _openBattle(craps, 600, 2, 5, 3);
        vm.prank(alice);
        craps.enterBattle(slot, 3 | (uint32(3) << 9) | (uint32(1) << 12), 1);
        vm.prank(bob);
        craps.enterBattle(slot, 3 | (uint32(3) << 12) | (uint32(1) << 15), 1);
        _closeOn(craps, slot, 7, uint256(keccak256("custom-split-word")));
        vm.recordLogs();
        craps.resolveSlot(slot, WHOLE_FIELD);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != _SPLIT_SIG, "a custom battle announced a split");
        }
        (uint256 an, uint256 ah) = craps.passCreditsOf(alice);
        (uint256 bn, uint256 bh) = craps.passCreditsOf(bob);
        assertEq(an + ah + bn + bh, 0, "a custom battle banked passes");
    }
}

/// @dev A coinflip stand-in that reads the pool back from INSIDE the credit it is being paid
///      through. What it sees is what any callee would see, so it is the strongest statement of
///      "state first, credit second" the architecture allows.
contract PoolWatcher {
    address public table;
    uint256 public seen;

    constructor(address t) {
        table = t;
    }

    function arm(address t) external {
        table = t;
    }

    function creditFlip(address, uint256) external {
        seen = ICrapsPool(table).progressivePool();
    }

    function creditFlipBatch(address[] calldata, uint256[] calldata) external {
        seen = ICrapsPool(table).progressivePool();
    }

    /// @dev The record door, present so a finalization that reaches it does not revert on this
    ///      double. It claims nothing: this watcher is about the progressive's ordering.
    function armDiceRunRecord(address, uint256) external pure returns (uint256) {
        return 0;
    }
}

interface ICrapsPool {
    function progressivePool() external view returns (uint256);
}
