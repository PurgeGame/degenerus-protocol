// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsViews} from "./CrapsViews.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsOracle} from "./CrapsOracle.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev Taps for the boosted engine and for an independent replay of it.
contract BoostHarness is CrapsViews {
    CrapsOracle public immutable oracle;

    constructor() {
        oracle = new CrapsOracle();
    }

    /// @dev The shipped engine under a schedule. `boost` is the packed pair the wrapper builds:
    ///      hot threshold in the low byte, suffix-profit percent above it.
    function slip(
        Craps.Bets calldata b,
        bytes32 seed,
        uint256 bankroll,
        uint256 goal,
        uint256 cap,
        address player,
        uint256 boost
    ) external pure returns (Craps.SlipResult memory) {
        return _settleSlip(b, seed, bankroll, goal, cap, _SLIP_ROLL_BUDGET, uint256(uint160(player)), boost);
    }

    /// @dev The shipped engine on the shipped bounds — what a settlement has to be compared
    ///      against.
    function slipScheduled(
        Craps.Bets calldata b,
        bytes32 seed,
        uint256 bankroll,
        uint256 goal,
        address player,
        uint256 boost
    ) external pure returns (Craps.SlipResult memory) {
        Craps.SlipResult memory r = _settleSlip(b, seed, bankroll * FLIP, goal * FLIP, _MAX_SLIP_HANDS, _SLIP_ROLL_BUDGET, uint256(uint160(player)), boost);
        r.bankrollIn /= FLIP;
        r.bankrollOut /= FLIP;
        r.peakBankroll /= FLIP;
        return r;
    }

    /// @dev The whole settlement of a bet, UNSCALED — a high seat's multiple applies after it, so
    ///      this is the one boosted base run a suite has to be able to see on its own.
    function settlementAt(uint256 betId) external view returns (Settlement memory) {
        return _settlementOf(betId, _loadBet(betId), _slotWindow(betId >> 64), _wordAt(_indexOf(betId >> 64)));
    }

    /// @dev The field's frozen entrant count — own seats and the day's appended seats.
    function fieldCountOf(uint64 slot) external view returns (uint256) {
        return _slotWindow(slot).entrants;
    }

    /// @dev The seed a BET's run is keyed on: the table's word and the WINDOW's slot.
    function seedForBet(uint64 slot) external view returns (bytes32) {
        return _crapsSeed(_wordAt(_indexOf(slot)), uint48(slot));
    }

    /// @dev The comparator a settlement folds, minus the standing the caller ORs in.
    function rankFor(Settlement memory s) external pure returns (uint256) {
        return _compositeOf(s);
    }

    function settlementForSeat(uint64 slot, uint256 seat) external view returns (Settlement memory result, uint256 id) {
        Window memory w = _slotWindow(slot);
        uint256 daySlot = uint256(slot) / 8 * 8;
        uint256 dayN = uint32(_dayTickets[daySlot]);
        uint256 ownN = w.entrants - dayN;
        id = seat <= ownN ? (uint256(slot) << 64) | seat : (daySlot << 64) | (seat - ownN);
        w.seat = uint64(seat);
        result = _settlementOf(id, _loadBet(id), w, _wordAt(_indexOf(slot)));
    }

    function longestOf(uint64 slot) external view returns (uint256) {
        return (_highField[bytes32(uint256(slot))] >> _HF_HOTTEST_SHIFT) & _HF_HOTTEST_MASK;
    }

    function bookDay(uint24 day, uint256 staked) external {
        _bookDay(day, staked, 0);
    }

    function bookHighDay(uint24 day, uint256 staked) external {
        _bookDay(day, staked, staked);
    }

    /// @dev The board a bet actually PLAYS: the chips it named, grown by the ones the table's
    ///      word placed. Rebuilt from the same published inputs a client replay uses, so a suite
    ///      can drive the bare engine with exactly the board a settlement drove it with.
    function playedBoardOf(uint256 betId, uint64 slot) external view returns (Craps.Bets memory board) {
        uint256 header = _loadBet(betId);
        Window memory w = _slotWindow(slot);
        uint256 word = _wordAt(_indexOf(slot));
        uint256 chipFlip = (w.played / 1) / _BONUS_CHIPS;
        uint256 packed = (header >> _BET_CHIPS_SHIFT) & _BET_CHIPS_MASK;
        uint256 placed;
        (, placed) = _packChips(uint32(packed));
        board = _boardFrom(packed, chipFlip);
        _scatterInto(
            board,
            uint256(keccak256(abi.encode(word, SCATTER_TAG, address(uint160(header))))),
            chipFlip,
            _BONUS_CHIPS - placed
        );
    }
}

/// @title The scheduled shooter profit boost
/// @notice House money added to what a shooter's board actually WON, on a schedule fixed before
///         the table's word existed. Everything here is about three separations: profit from
///         principal, one player's schedule from the next's, and a protocol-scheduled window from
///         a battle somebody else opened.
contract CrapsShooterBoostTest is CrapsPins {
    BoostHarness internal craps;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant _SURVIVAL_TAG = 0x537572766976616c; // "Survival"

    /// @dev A word whose period-1 window is a routine table, and the day driver's default.
    uint256 internal constant PLAIN_WORD = 40 << 8;
    uint256 internal constant PER = 1;

    function setUp() public {
        _installPins();
        craps = new BoostHarness();
        // Genesis is a Craps warm-up day; every fixture plays from genesis + 1.
        vm.warp(block.timestamp + 1 days);
        _setIndex(0);
        uint256 floor_ = craps.SYBIL_SCORE_FLOOR();
        game.setScore(alice, floor_);
        game.setScore(bob, floor_);
    }

    // ── Restated primitives ─────────────────────────────────────────────────

    function _survivalCoin(bytes32 seed, uint256 n, address player) internal pure returns (bool) {
        return uint256(keccak256(abi.encode(_SURVIVAL_TAG, seed, n, player))) & 1 == 1;
    }

    function _terms(uint256 threshold, uint256 pct) internal pure returns (uint256) {
        return threshold | (pct << 8);
    }

    /// @dev Three chips on the line, two on the six, two on the hard eight — a board that wins on
    ///      the light side often enough for a boost to have something to work on.
    function _mixed() internal pure returns (Craps.Bets memory b) {
        b.passLine = 3 * 60;
        b.place6 = 2 * 60;
        b.hard8 = 2 * 60;
    }

    function _dark() internal pure returns (Craps.Bets memory b) {
        b.dontPass = 7 * 60;
    }

    // ════════════════════════════════════════════════════════════════════════
    // The schedule itself
    // ════════════════════════════════════════════════════════════════════════

    /// @dev The exact eight-row continuum: more player choice means fewer scattered chips and a
    ///      smaller scheduled shooter-profit subsidy.
    function test_theScheduleCarriesTheExactPlacedChipTerms() public view {
        uint8[8] memory uplift = [uint8(30), 25, 20, 18, 14, 10, 7, 5];
        for (uint256 placed = 0; placed < 8; ++placed) {
            assertEq(craps.shooterBoostTerms(placed), _terms(12, uplift[placed]), "a boost row moved");
        }
    }

    function test_hotActivationIsSharedAndDiceDoNotMove() public view {
        for (uint256 k; k < 50; ++k) {
            bytes32 seed = keccak256(abi.encode("shared-hot", k));
            Craps.SlipResult memory a = craps.slip(_mixed(), seed, 1_000_000e18, 0, 1, alice, _terms(12, 30));
            Craps.SlipResult memory b = craps.slip(_mixed(), seed, 1_000_000e18, 0, 1, bob, _terms(12, 30));
            Craps.SlipResult memory bare = craps.slip(_mixed(), seed, 1_000_000e18, 0, 1, alice, 0);
            assertEq(a.bankrollOut, b.bankrollOut, "owner changed duration bonus");
            assertEq(a.totalRolls, bare.totalRolls, "bonus changed dice");
            if (a.totalRolls <= 12) assertEq(a.bankrollOut, bare.bankrollOut, "early profit boosted");
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // Profit, and never principal
    // ════════════════════════════════════════════════════════════════════════

    /// @dev THE LIGHT SIDE PAYS AND STAYS, so every wei it credits is profit. Graded hand by hand
    ///      against the oracle's own books: what the dice paid is `profit`, and the only thing
    ///      that can sit outside it is a stake handed back — which on a hand that sevens out is
    ///      nothing at all.
    function test_lightSideWinningsAreProfitToTheLastWei() public view {
        Craps.Bets memory b = _mixed();
        CrapsOracle oracle = craps.oracle();
        uint256 graded;
        for (uint256 i = 0; i < 200; ++i) {
            bytes32 hs = oracle.handSeed(keccak256("light"), i);
            CrapsOracle.Outcome memory o = oracle.resolveHand(b, hs);
            if (o.truncated) continue; // astronomically rare; graded on its own below
            // No dark wager on this board, so nothing returns a stake: the whole credit is
            // winnings and the boost base is the credit itself.
            assertEq(o.profit, o.returned, "a light-only hand booked principal as profit");
            if (o.returned != 0) ++graded;
        }
        assertGt(graded, 100, "the fixture found too few paying hands to grade");
    }

    /// @dev THE DARK SIDE IS THE EXCEPTION: it is the one wager on this board that hands its own
    ///      stake back when it wins, and that stake is principal. Only the 3:4 is boostable.
    function test_aDarkWinBoostsOnlyItsThreeQuartersProfit() public view {
        Craps.Bets memory b = _dark();
        CrapsOracle oracle = craps.oracle();
        uint256 stake = uint256(b.dontPass) * 1 ether;
        uint256 profit = (uint256(b.dontPass) * 3 ether) / 4;
        uint256 wins;
        uint256 losses;
        for (uint256 i = 0; i < 200; ++i) {
            CrapsOracle.Outcome memory o = oracle.resolveHand(b, oracle.handSeed(keccak256("dark"), i));
            if (o.truncated) continue;
            if (o.returned == 0) {
                ++losses;
                continue;
            }
            ++wins;
            assertEq(o.returned, stake + profit, "a dark win returned other than stake plus 3:4");
            assertEq(o.profit, profit, "a dark win booked its own stake as profit");
        }
        assertGt(wins, 50, "the fixture found too few dark wins");
        assertGt(losses, 50, "the fixture found too few dark losses");

        // And end to end: a fully scheduled run boosts the 3:4 and nothing else, so a 100% board
        // of dark wagers grows by exactly the boost on its winnings.
        Craps.SlipResult memory bare = craps.slip(b, keccak256("dark"), 4200e18, 0, 8, alice, 0);
        Craps.SlipResult memory boosted = craps.slip(b, keccak256("dark"), 4200e18, 0, 8, alice, _terms(12, 40));
        assertEq(boosted.handsPlayed, bare.handsPlayed, "the schedule changed the run's shape");
        // The gap can only be 40% of the PROFIT paid, never 40% of the whole return.
        uint256 gap = boosted.bankrollOut - bare.bankrollOut;
        assertEq(boosted.bankrollOut, _replay(b, keccak256("dark"), 4200e18, 8, alice, 12, 40, false),
            "dark bonus must use only late profit");
        assertLt(gap, ((stake + profit) * 8 * 40) / 100, "the boost reached past the 3:4");
    }

    /// @dev A ROLL-CAP TRUNCATION REFUNDS STAKE, AND STAKE IS NOT PROFIT. Reachable only with
    ///      scripted dice — a real hand hits 512 rolls at odds around 1e-28 — so it is graded on
    ///      the oracle, which is where the distinction is drawn independently of production.
    function test_aRollCapRefundIsNotProfit() public view {
        Craps.Bets memory b;
        b.passLine = 600;
        CrapsOracle oracle = craps.oracle();
        // A point, then 511 rolls that decide nothing: no seven, never the point, no light win.
        uint8[] memory dice = new uint8[](2 * 512);
        dice[0] = 2;
        dice[1] = 2; // come-out 4: the point
        for (uint256 i = 1; i < 512; ++i) {
            dice[2 * i] = 1;
            dice[2 * i + 1] = 2; // a 3 during the point phase: nothing happens
        }
        CrapsOracle.Outcome memory o = oracle.resolveHandWithScriptedDice(b, dice, bytes32(0));
        assertTrue(o.truncated, "the scripted hand did not reach the roll cap");
        assertEq(o.returned, uint256(b.passLine) * 1 ether, "the cap did not refund the live line");
        assertEq(o.profit, 0, "a refunded stake was booked as profit");
    }

    /// @dev THE SURVIVAL COIN IS CAPITAL, NOT WINNINGS. It doubles the bankroll between shooters,
    ///      outside any hand — so a schedule can never take a percentage of it. Proven on a run
    ///      that actually fires the coin.
    function test_theSurvivalDoublingIsNeverBoosted() public view {
        Craps.Bets memory b = _mixed();
        uint256 stake = craps.stakeFor(b);
        bytes32 seed = keccak256("coin");
        // Start between half a round and a whole one: the very first affordability check takes
        // the coin, and the fixture is chosen so it survives.
        uint256 start = (stake * 3) / 4;
        assertTrue(_survivalCoin(seed, 0, alice), "the fixture's first coin loses");
        Craps.SlipResult memory r = craps.slip(b, seed, start, 0, 1, alice, _terms(12, 40));
        assertEq(r.handsPlayed, 1, "the run did not play the one shooter it was funded for");
        // The doubling is exactly 2x and lands before the hand, so the whole boost that follows
        // is a percentage of the HAND's winnings and none of it a percentage of the double.
        CrapsOracle.SlipResult memory ox =
            craps.oracle().resolveSlipBoosted(b, seed, start, 0, 1, alice, _terms(12, 40));
        assertEq(r.bankrollOut, ox.bankrollOut, "the engine and the oracle disagree across a coin");
        assertEq(ox.bankrollIn, start, "the oracle started somewhere else");
    }

    // ════════════════════════════════════════════════════════════════════════
    // Flooring, and the escalator
    // ════════════════════════════════════════════════════════════════════════

    /// @dev FLOORED ONCE, ON THE BASE HAND, BEFORE THE ESCALATOR. A round two units deep is
    ///      exactly twice the boosted base hand — not the boost recomputed on a doubled figure,
    ///      which would round differently and pay a different number.
    function test_theBoostIsFlooredOncePerBaseHandBeforeScaling() public view {
        // A board whose winnings do not divide by the boost percentage: place 6 pays 7:6, so a
        // hand's profit is not a whole number of hundredths and the two orders can disagree.
        Craps.Bets memory b;
        b.place6 = 5;
        b.passLine = 5;
        CrapsOracle oracle = craps.oracle();
        bytes32 seed = keccak256("floor");

        uint256 pct = 40;
        uint256 straddles;
        for (uint256 h = 0; h < 40; ++h) {
            CrapsOracle.Outcome memory o = oracle.resolveHand(b, oracle.handSeed(seed, h));
            if (o.profit == 0) continue;
            uint256 q = craps.escOf(h);
            if (q < 2) continue;
            uint256 floorFirst = q * (o.returned + (o.hotProfit * pct) / 100);
            uint256 floorAfter = q * o.returned + (q * o.hotProfit * pct) / 100;
            if (floorFirst != floorAfter) ++straddles;
        }
        assertGt(straddles, 0, "the fixture never straddles the flooring order, so it proves nothing");

        // And the engine takes the FIRST order. Replayed independently, hand by hand, from the
        // oracle's unboosted outcomes.
        for (uint256 cap = 6; cap <= 40; cap += 2) {
            Craps.SlipResult memory r = craps.slip(b, seed, 900_000e18, 0, cap, alice, _terms(12, pct));
            assertEq(
                r.bankrollOut,
                _replay(b, seed, 900_000e18, cap, alice, 12, pct, false),
                "the engine did not floor the boost once on the base hand"
            );
        }
    }

    /// @dev The wrong order is a DIFFERENT number on this fixture, so the assertion above is not
    ///      satisfied by both. Stated separately so the two can never quietly converge.
    function test_flooringAfterTheEscalatorWouldPayDifferently() public view {
        Craps.Bets memory b;
        b.place6 = 5;
        b.passLine = 5;
        bytes32 seed = keccak256("floor");
        uint256 right = _replay(b, seed, 900_000e18, 40, alice, 12, 40, false);
        uint256 wrong = _replay(b, seed, 900_000e18, 40, alice, 12, 40, true);
        assertTrue(right != wrong, "the two flooring orders agree, so the order is untested");
        assertEq(craps.slip(b, seed, 900_000e18, 0, 40, alice, _terms(12, 40)).bankrollOut, right, "wrong order");
    }

    /// @dev An INDEPENDENT walk of the engine's loop: escalator, affordability coin, per-hand
    ///      settlement from the oracle, and the boost applied where production applies it. With
    ///      `floorAfterScale` the boost is instead taken on the scaled round, which is the
    ///      mis-ordering the fixtures above are built to separate.
    function _replay(
        Craps.Bets memory b,
        bytes32 seed,
        uint256 bankroll,
        uint256 cap,
        address player,
        uint256 threshold,
        uint256 pct,
        bool floorAfterScale
    ) internal view returns (uint256) {
        CrapsOracle oracle = craps.oracle();
        uint256 stake = craps.stakeFor(b);
        for (uint256 h = 0; h < cap; ++h) {
            uint256 q = craps.escOf(h);
            uint256 need = q * stake;
            if (bankroll * 2 < need) return bankroll;
            if (bankroll < need) {
                if (!_survivalCoin(seed, h, player)) return 0;
                bankroll += bankroll;
            }
            CrapsOracle.Outcome memory o = oracle.resolveHand(b, oracle.handSeed(seed, h));
            uint256 round = q * o.returned;
            if (o.rolls > threshold) {
                round = floorAfterScale
                    ? round + (q * o.hotProfit * pct) / 100
                    : q * (o.returned + (o.hotProfit * pct) / 100);
            }
            bankroll = bankroll - need + round;
        }
        return bankroll;
    }

    // ════════════════════════════════════════════════════════════════════════
    // What the boost is allowed to change
    // ════════════════════════════════════════════════════════════════════════

    /// @dev IT MAY DECIDE THE RUN. The boost lands in the bankroll before the next goal, bound and
    ///      affordability check, so it can cross a target a shooter early or buy a round the run
    ///      could not otherwise afford. That is deliberate, and it is what makes the schedule
    ///      worth having rather than a payout adjustment at the end.
    function test_theBoostMayCrossAGoalOrBuyAnotherRound() public view {
        Craps.Bets memory b = _mixed();
        uint256 crossedEarlier;
        uint256 outlasted;
        for (uint256 i = 0; i < 120; ++i) {
            bytes32 seed = keccak256(abi.encode("decide", i));
            uint256 goal = 6000e18 * 5;
            Craps.SlipResult memory bare = craps.slip(b, seed, 6000e18, goal, 40, alice, 0);
            Craps.SlipResult memory up = craps.slip(b, seed, 6000e18, goal, 40, alice, _terms(12, 40));
            if (up.stop == Craps.SlipStop.Goal && bare.stop != Craps.SlipStop.Goal) ++crossedEarlier;
            else if (
                up.stop == Craps.SlipStop.Goal && bare.stop == Craps.SlipStop.Goal
                    && up.handsPlayed < bare.handsPlayed
            ) ++crossedEarlier;
            if (up.handsPlayed > bare.handsPlayed) ++outlasted;
        }
        assertGt(crossedEarlier, 0, "no boosted run ever reached its target sooner");
        assertGt(outlasted, 0, "no boosted run ever bought a round the bare one could not");
    }

    // ════════════════════════════════════════════════════════════════════════
    // Where the schedule applies, and where it does not
    // ════════════════════════════════════════════════════════════════════════

    /// @dev A CUSTOM BATTLE IS HANDED NO SCHEDULE at every accepted placed-chip count, even on a
    ///      target the day's own windows draw. Each settles byte for byte against the bare engine.
    function test_aCustomBattleIsNeverBoosted() public {
        uint16[3] memory goals = [uint16(5), 10, 50];
        for (uint256 placed = 0; placed <= 7; ++placed) {
            uint256 trialSnapshot = vm.snapshotState();
            uint256 goalMult = goals[placed % goals.length];
            uint64 slot = _openBattle(craps, 600, 5, uint16(goalMult), 0);
            vm.prank(alice);
            uint256 betId = craps.enterBattle(slot, _placed(placed), 1);
            _closeOn(
                craps, slot, uint48(placed & 1), uint256(keccak256(abi.encode("custom", placed)))
            );

            CrapsBattle.Settlement memory s = craps.settlementAt(betId);
            // The terms this fixture opened the battle on: a 600-FLIP round, five rounds deep.
            uint256 bank = 600 * 5e18;
            uint256 goal = bank * goalMult;
            Craps.SlipResult memory bare = craps.slip(
                _scattered(betId, slot), craps.seedForBet(slot), bank, goal, craps.MAX_SLIP_HANDS(), alice, 0
            );
            assertEq(s.won, bare.bankrollOut / 1e18, "a custom battle settled to something the bare engine did not");
            assertEq(s.peak, bare.peakBankroll / 1e18, "a custom boost changed the run's high point");
            assertEq(s.handsPlayed, bare.handsPlayed, "a custom boost changed the shooter count");
            assertEq(s.totalRolls, bare.totalRolls, "a custom boost changed the dice walk");
            assertEq(uint8(s.stop), uint8(bare.stop), "a custom boost changed the stop class");
            vm.revertToStateAndDelete(trialSnapshot);
        }
    }

    /// @dev A SCHEDULED WINDOW applies each of the eight rows to the ticket whose stored count
    ///      names it. Every run is compared against the shipped engine driven with that exact row.
    function test_aScheduledWindowAppliesEveryTicketsOwnSchedule() public {
        vm.warp(vm.getBlockTimestamp() + 10 days);
        _warpToDayStart();
        uint24 day = craps.currentDayIndex();
        craps.bookDay(day - 1, 3_000_000);
        _setDailyWord(day, PLAIN_WORD);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();

        vm.warp(vm.getBlockTimestamp() + 1 hours);
        uint256[8] memory ids;
        address[8] memory players;
        for (uint256 placed = 0; placed <= 7; ++placed) {
            address player = makeAddr(string(abi.encodePacked("boost-row", placed)));
            players[placed] = player;
            game.setScore(player, craps.SYBIL_SCORE_FLOOR());
            vm.prank(player);
            ids[placed] = craps.enterBonusBattle(PER, _placed(placed), 1);
        }

        uint64 slot = uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + PER + 1);
        vm.warp(vm.getBlockTimestamp() + 7 hours);
        uint48 index = craps.armWindow(slot);
        _setWord(index, uint256(keccak256("all-boost-rows")));

        (uint128 bank, uint128 goal,,,,) = craps.bonusTermsFor(day, PER);
        bytes32 seed = craps.seedForBet(slot);
        for (uint256 placed = 0; placed <= 7; ++placed) {
            assertEq(
                craps.settlementAt(ids[placed]).won,
                craps.slipScheduled(
                    _scattered(ids[placed], slot),
                    seed,
                    bank,
                    goal,
                    players[placed],
                    craps.shooterBoostTerms(placed) | _turn(seed, placed + 1, craps.fieldCountOf(slot))
                ).bankrollOut,
                "a seat did not settle under its placed-chip row"
            );
        }
        assertLe(index, 1, "the window shut onto an invalid physical buffer");
    }

    /// @dev A BLANK TICKET IS CLASSIFIED FROM THE WORD IT WAS STORED WITH, never from the ten
    ///      chips it ends up playing. The scatter fills a blank board to ten, so a settlement that
    ///      read the resolved board would call every blank ticket picked and pay it a third as
    ///      often.
    function test_theScatteredBoardNeverReclassifiesABlankTicket() public {
        (uint24 day, uint64 slot,) = _openAndSeatBoth();
        (uint128 bank, uint128 goal,,,,) = craps.bonusTermsFor(day, PER);
        uint256 blankId = (uint256(slot) << 64) | 2;

        // The board it PLAYS holds all ten chips, exactly like a picked ticket's does — which is
        // precisely why the classification cannot be read off it.
        Craps.Bets memory played = _scattered(blankId, slot);
        assertEq(craps.betOf(blankId).chips, 0, "the fixture's blank ticket stored chips");
        (,, uint256 posted,,,) = craps.bonusTermsFor(day, PER);
        assertEq(craps.stakeFor(played), (posted * 10) / 7, "the scattered blank board is not the whole round");

        // And it settles under row zero, which row seven would not reproduce. Search for a table
        // word that actually SEPARATES those endpoint rows: a run in which no shooter draws
        // either boost settles identically under both, and would grade nothing.
        bool separated;
        for (uint256 i = 0; i < 64 && !separated; ++i) {
            _setWord(craps.indexOfSlot(slot), uint256(keccak256(abi.encode("classify", i))));
            played = _scattered(blankId, slot);
            bytes32 s2 = craps.seedForBet(slot);
            uint256 b2 = craps.slipScheduled(played, s2, bank, goal, bob, craps.shooterBoostTerms(0) | _turn(s2, 2, craps.fieldCountOf(slot)))
                .bankrollOut;
            uint256 p2 = craps.slipScheduled(played, s2, bank, goal, bob, craps.shooterBoostTerms(7) | _turn(s2, 2, craps.fieldCountOf(slot)))
                .bankrollOut;
            if (b2 == p2) continue;
            separated = true;
            assertEq(craps.settlementAt(blankId).won, b2, "a zero-chip ticket did not take row zero");
        }
        assertTrue(separated, "no word separated the two schedules, so the classification is untested");
    }

    /// @dev PREVIEW AND PAYMENT ARE ONE COMPUTATION. A boosted settlement quotes exactly what it
    ///      pays — stop, shooters, bankroll and rank all come off the same call.
    function test_aBoostedSettlementPreviewsExactlyWhatItPays() public {
        (, uint64 slot,) = _openAndSeatBoth();
        uint256 pickedId = (uint256(slot) << 64) | 1;
        uint256 blankId = (uint256(slot) << 64) | 2;

        (uint256 wonA, uint256 paidA) = craps.previewSettlement(pickedId);
        (uint256 wonB, uint256 paidB) = craps.previewSettlement(blankId);
        CrapsBattle.Settlement memory sA = craps.settlementAt(pickedId);
        CrapsBattle.Settlement memory sB = craps.settlementAt(blankId);
        assertEq(wonA, sA.won, "the picked preview quoted a different run");
        assertEq(paidA, sA.paid, "the picked preview quoted a different payment");
        assertEq(wonB, sB.won, "the blank preview quoted a different run");
        assertEq(paidB, sB.paid, "the blank preview quoted a different payment");

        // Deterministic, and the account closes: the quote does not move between two identical
        // calls, a bust pays nothing, and a payment sits within one rounding granule of the run.
        (uint256 againA,) = craps.previewSettlement(pickedId);
        assertEq(againA, wonA, "the preview moved between two identical calls");
        assertGt(sA.handsPlayed + sB.handsPlayed, 0, "neither seat played a shooter");
        if (sA.stop == Craps.SlipStop.Bust) assertEq(sA.paid, 0, "a busted seat was paid");
        else assertApproxEqAbs(sA.paid, sA.won, 100, "the payment left the run behind");
        if (sB.stop == Craps.SlipStop.Bust) assertEq(sB.paid, 0, "a busted seat was paid");
        else assertApproxEqAbs(sB.paid, sB.won, 100, "the payment left the run behind");

        // THE COMPOSITE TOO. A battle ranks on the stop, the high point, the shooter count and
        // the ending bankroll, every one of which comes off this same call — so pinning the
        // settlement pins the score the scoreboard folds.
        assertEq(
            craps.rankFor(sA),
            craps.rankFor(craps.settlementAt(pickedId)),
            "the composite moved between two reads of one settlement"
        );

        // And the WALK pays what was quoted: the settled event carries the same figures.
        vm.recordLogs();
        craps.settleSlot(slot, WHOLE_FIELD);
        (uint256 settledWonA, uint256 settledPaidA) = _settledOf(vm.getRecordedLogs(), pickedId);
        assertEq(settledWonA, wonA, "the settled run is not the previewed one");
        assertEq(settledPaidA, paidA, "the settled payment is not the previewed one");
    }

    /// @dev `CrapsBetSettled(betId, player, won, paid)` for one bet, out of a settle walk's logs.
    function _settledOf(Vm.Log[] memory logs, uint256 betId) internal pure returns (uint256 won, uint256 paid) {
        bytes32 sig = keccak256("CrapsBetSettled(uint256,address,uint256,uint256)");
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length == 0 || logs[i].topics[0] != sig) continue;
            if (uint256(logs[i].topics[1]) != betId) continue;
            (won, paid) = abi.decode(logs[i].data, (uint256, uint256));
            return (won, paid);
        }
        revert("no settled event for that bet");
    }

    /// @dev THE DIFFERENTIAL, under a schedule. Production reaches eligible profit by subtracting
    ///      a winning dark wager's principal out of one running total at the end of the hand; the
    ///      oracle reaches it by adding winnings up as the dice pay them. Two derivations, one
    ///      number — graded over every board shape the table admits and both of the schedule's
    ///      rates, with the ordinary run also graded so the boost cannot be hiding a difference
    ///      that was there anyway.
    function test_theBoostedEngineMatchesTheOracleOnEveryBoardShape() public view {
        CrapsOracle oracle = craps.oracle();
        Craps.Bets[5] memory boards;
        boards[0] = _mixed();
        boards[1] = _dark();
        boards[2].place4 = 240;
        boards[2].place10 = 180;
        boards[3].passLine = 240;
        boards[3].dontPass = 0;
        boards[3].hard4 = 180;
        boards[4].passLine = 120;
        boards[4].place6 = 120;
        boards[4].dontPass = 0;
        boards[4].hard8 = 180;

        uint256[3] memory schedules =
            [uint256(0), _terms(12, 40), _terms(12, 6)];

        uint256 graded;
        for (uint256 i = 0; i < boards.length; ++i) {
            for (uint256 j = 0; j < schedules.length; ++j) {
                for (uint256 k = 0; k < 6; ++k) {
                    bytes32 seed = keccak256(abi.encode("diff", i, j, k));
                    address who = k % 2 == 0 ? alice : bob;
                    uint256 bank = 3000e18 * (1 + (k % 3));
                    Craps.SlipResult memory got =
                        craps.slip(boards[i], seed, bank, bank * 10, 48, who, schedules[j]);
                    CrapsOracle.SlipResult memory want =
                        oracle.resolveSlipBoosted(boards[i], seed, bank, bank * 10, 48, who, schedules[j]);
                    assertEq(got.bankrollOut, want.bankrollOut, "the two engines disagree about the money");
                    assertEq(got.handsPlayed, want.handsPlayed, "the two engines disagree about the shooters");
                    assertEq(got.unitsPlayed, want.unitsPlayed, "the two engines disagree about the handle");
                    assertEq(got.totalRolls, want.totalRolls, "the two engines disagree about the dice");
                    assertEq(uint8(got.stop), uint8(want.stop), "the two engines disagree about the stop");
                    ++graded;
                }
            }
        }
        assertEq(graded, 90, "the differential did not run the whole grid");
    }

    /// @dev A HIGH SEAT BUYS COPIES OF ONE RUN, NOT A BETTER ONE. It takes exactly one schedule
    ///      over the shared shooters, and the day's multiple scales that single boosted base run
    ///      once — it does not draw a fresh eligibility roll per copy, which would pay a high seat
    ///      a different rate from everyone else at the same table.
    function test_aHighSeatScalesOneBoostedRunAndDrawsOneSchedule() public {
        vm.warp(vm.getBlockTimestamp() + 10 days);
        _warpToDayStart();
        uint24 day = craps.currentDayIndex();
        craps.bookDay(day - 1, 3_000_000);
        _setDailyWord(day, PLAIN_WORD);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();

        uint256 hm = craps.highMultForDay(day);
        assertGt(hm, 1, "the fixture's day drew no high lane");
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        vm.prank(alice);
        craps.enterBonusBattle(PER, _sevenChips(), uint16(hm));

        uint64 slot = uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + PER + 1);
        vm.warp(vm.getBlockTimestamp() + 7 hours);
        uint48 index = craps.armWindow(slot);
        _setWord(index, uint256(keccak256("high-boost")));

        uint256 betId = (uint256(slot) << 64) | 1;
        (uint128 bank, uint128 goal,,,,) = craps.bonusTermsFor(day, PER);

        // ONE base run, drawn under the ONE schedule its ticket names.
        uint256 base = craps.slipScheduled(
            _scattered(betId, slot),
            craps.seedForBet(slot),
            bank,
            goal,
            alice,
            craps.shooterBoostTerms(7) | _turn(craps.seedForBet(slot), 1, craps.fieldCountOf(slot))
        ).bankrollOut;
        assertEq(craps.settlementAt(betId).won, base, "the high seat's base run took a different schedule");

        // And the multiple scales THAT, exactly once.
        (uint256 won,) = craps.previewSettlement(betId);
        assertEq(won, base * hm, "the high multiple did not scale one boosted base run");
    }

    /// @dev A window's slice of its day is a function of its PERIOD and SIZE. Fixing the goal at
    ///      5x leaves no goal-weighting branch in the allocation.
    function test_theFixedGoalNeverAddsAllocationWeighting() public {
        vm.warp(vm.getBlockTimestamp() + 10 days);
        _warpToDayStart();
        uint24 day = craps.currentDayIndex();
        for (uint256 i = 1; i <= craps.BOOST_ACTION_WINDOW_DAYS(); ++i) {
            craps.bookDay(day - uint24(i), 6_000_000);
        }

        uint256 matchingPairs;
        for (uint256 w = 0; w < 80; ++w) {
            _setDailyWord(day, uint256(keccak256(abi.encode("goalweight", w))));
            // Per tier, within THIS day: every routine window takes the same share.
            uint256[4] memory shareOf;
            for (uint256 p = 0; p + 1 < craps.BONUS_PERIODS_PER_DAY(); ++p) {
                (uint128 bank, uint128 goal,,,,) = craps.bonusTermsFor(day, p);
                if (bank == 0) continue;
                uint256 mult = uint256(goal) / uint256(bank);
                assertEq(mult, craps.SCHED_GOAL(), "a routine window is not goal 5x");
                uint256 tier = craps.tierPickAt(craps.dailyWordAt(day), p) + 1;
                uint256 share = craps.boostBaseOf(uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + p + 1));
                assertGt(share, 0, "a routine window took nothing, so the sweep measures nothing");
                if (shareOf[tier] == 0) {
                    shareOf[tier] = share;
                } else {
                    assertEq(shareOf[tier], share, "two windows of one tier took different shares");
                    ++matchingPairs;
                }
            }
        }
        assertGt(matchingPairs, 40, "the sweep never repeated a tier, so it proves nothing");

        // Nothing else is on the schedule — the event window included — and depth is five rounds.
        for (uint256 w = 0; w < 80; ++w) {
            _setDailyWord(day, uint256(keccak256(abi.encode("goalweight", w))));
            for (uint256 p = 0; p < craps.BONUS_PERIODS_PER_DAY(); ++p) {
                (uint128 bank, uint128 goal,,,,) = craps.bonusTermsFor(day, p);
                if (bank == 0) continue;
                uint256 mult = uint256(goal) / uint256(bank);
                assertEq(mult, craps.SCHED_GOAL(), "a scheduled window is not goal 5x");
                uint256 round = craps.roundOf(uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + p + 1));
                assertEq(uint256(bank) / round, craps.SCHED_BANK_MULT(), "a scheduled window is not five deep");
            }
        }
    }

    /// @dev THE SPLIT CANNOT MANUFACTURE A WEI. Whatever the action, the two lanes together never
    ///      exceed the rate on it, the high lane's two shares always sum back to its component, and
    ///      the one-wei split remainder lands on the high side by construction. Swept over amounts
    ///      chosen to leave a remainder at every division in the chain.
    function test_integerRoundingNeverCreatesAnExtraComponent() public {
        vm.warp(vm.getBlockTimestamp() + 10 days);
        uint24 day = craps.currentDayIndex();
        uint256 base = craps.BASE_MAIN_BUDGET();
        uint256 days_ = craps.BOOST_ACTION_WINDOW_DAYS();

        for (uint256 k = 0; k < 12; ++k) {
            uint24 d = day + uint24(k * days_ * 2);
            // Deliberately awkward: not divisible by 7, by 5, or by the bps denominator.
            uint256 high = 1_000_003 + k * 9_973;
            uint256 regular = 3_000_007 + k * 7_919;
            for (uint256 i = 1; i <= days_; ++i) {
                craps.bookDay(d - uint24(i), regular);
                craps.bookHighDay(d - uint24(i), high);
            }
            (uint256 m, uint256 h) = craps.drawBudgetsFor(d);
            uint256 rate = craps.BOOST_ACTION_BPS();
            uint256 den = craps.BPS_DENOMINATOR();
            // Never MORE than the rate on the action, whatever the flooring did.
            assertLe(m - base + h, ((regular + high) * rate) / den, "rounding paid out more than the rate");
            // The high lane's own component conserves across the two-way split.
            uint256 eh = (high * rate) / den;
            uint256 toMain = (eh * craps.HIGH_MAIN_NUM()) / craps.HIGH_MAIN_DEN();
            assertEq(h, eh - toMain, "the high split lost or made a wei");
            assertEq(m, base + (regular * rate) / den + toMain, "the main lane is not base + its two components");
            // The remainder of the two-way split sits with the HIGH lane, never the main one.
            assertGe(h * craps.HIGH_MAIN_DEN(), eh * (craps.HIGH_MAIN_DEN() - craps.HIGH_MAIN_NUM()), "remainder");
        }
    }

    /// @dev NOTHING THE TABLE EMITS EVER BOOKS AS ACTION. A day's action is the BANKROLL its
    ///      settled seats put up and nothing else: not the bounties they posted, not the boost the
    ///      pot handed a winner, not the credits the runs came home with. Otherwise a subsidy
    ///      would size the next week's subsidy, and the schedule would feed on itself.
    function test_emittedValueNeverBooksAsAction() public {
        (uint24 day, uint64 slot,) = _openAndSeatBoth();

        (uint128 bank,,, uint256 battleStake, uint256 boostQuote,) = craps.bonusTermsFor(day, PER);
        assertGt(boostQuote, 0, "the fixture's window put up no house money");
        assertGt(battleStake, 0, "the fixture's window carried no bounty");

        vm.recordLogs();
        craps.settleSlot(slot, WHOLE_FIELD);
        PaidOut[] memory pots = _potsIn(vm.getRecordedLogs());
        assertEq(pots.length, 1, "the window paid other than one pot");
        assertGt(pots[0].amount, 0, "the fixture's pot paid nothing");

        // FOUR SEATS SETTLED IN THIS WINDOW — the picked ticket, the blank one, and the house
        // and vault day tickets — and the day's books hold exactly their four bankrolls. Not the
        // bounties they posted, not the boost the pot just paid, not a wei of run credit.
        assertEq(
            craps.dayStaked(day),
            4 * uint256(bank),
            "the day booked something other than the bankrolls its seats put up"
        );
        assertEq(craps.highStakedOf(day), 0, "an ordinary field booked high action");
        // And the pot it paid was strictly larger than a bounty, so real house money moved and
        // still did not land in the books.
        assertGt(pots[0].amount, 2 * battleStake, "the pot carried no house money, so nothing was at risk");
    }

    // ── Fixture plumbing ────────────────────────────────────────────────────

    function _sevenChips() internal pure returns (Craps.Bets memory b) {
        b.passLine = 3;
        b.place6 = 2;
        b.hard8 = 2;
    }

    /// @dev Any accepted placed-chip count, spread under the three-per-leg ceiling.

    // ════════════════════════════════════════════════════════════════════════
    // The rotating shooter
    // ════════════════════════════════════════════════════════════════════════

    uint256 internal constant _ROTATION_TAG = 0x526f746174696e6753686f6f746572; // "RotatingShooter"

    /// @dev The published derivation, restated: one start per field off the slot-keyed seed, then
    ///      the seat's distance from it. Returns the packed one-based turn, or zero past the bound.
    function _turn(bytes32 seed, uint256 seat, uint256 n) internal pure returns (uint256) {
        uint256 start = 1 + uint256(keccak256(abi.encode(_ROTATION_TAG, seed))) % n;
        uint256 offset = (seat + n - start) % n;
        return offset < 512 ? (offset + 1) << 16 : 0;
    }

    /// @dev Every seat in one field takes the SAME start and settles at its OWN turn — checked
    ///      against the bare engine driven with an independently restated rotation term.
    function test_everySeatSettlesAtItsOwnTurnOffOneSharedStart() public {
        vm.warp(vm.getBlockTimestamp() + 10 days);
        _warpToDayStart();
        uint24 day = craps.currentDayIndex();
        craps.bookDay(day - 1, 3_000_000);
        _setDailyWord(day, PLAIN_WORD);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        vm.warp(vm.getBlockTimestamp() + 1 hours);

        uint256 n = 13;
        uint256[] memory ids = new uint256[](n);
        address[] memory players = new address[](n);
        for (uint256 i = 0; i < n; ++i) {
            address player = makeAddr(string(abi.encodePacked("rot", i)));
            players[i] = player;
            game.setScore(player, craps.SYBIL_SCORE_FLOOR());
            vm.prank(player);
            ids[i] = craps.enterBonusBattle(PER, _placed(i % 8), 1);
        }
        uint64 slot = uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + PER + 1);
        vm.warp(vm.getBlockTimestamp() + 7 hours);
        uint48 index = craps.armWindow(slot);
        // The personal bonus now requires a hot hand. Choose a shared first hand
        // with late place profit so its named shooter's extra is observable.
        for (uint256 k; k < 100; ++k) {
            _setWord(index, uint256(keccak256(abi.encode("rotation-field", k))));
            CrapsOracle.Outcome memory first = craps.oracle().resolveHand(
                _mixed(), craps.oracle().handSeed(craps.seedForBet(slot), 0)
            );
            if (first.hotProfit != 0) break;
        }
        (uint128 bank, uint128 goal,,,,) = craps.bonusTermsFor(day, PER);
        bytes32 seed = craps.seedForBet(slot);

        uint256 moved;
        uint256 field = craps.fieldCountOf(slot);
        assertGe(field, n, "the frozen field is smaller than the seats entered");
        for (uint256 i = 0; i < n; ++i) {
            uint256 seat = uint64(ids[i]);
            assertEq(seat, i + 1, "seats are not dense");
            uint256 terms = craps.shooterBoostTerms(i % 8);
            uint256 want = craps.slipScheduled(_scattered(ids[i], slot), seed, bank, goal, players[i], terms | _turn(seed, seat, field)).bankrollOut;
            assertEq(craps.settlementAt(ids[i]).won, want, "a seat did not settle at its rotation turn");
            if (want != craps.slipScheduled(_scattered(ids[i], slot), seed, bank, goal, players[i], terms).bankrollOut) ++moved;
        }
        assertGt(moved, 0, "no seat's money moved: the rotation is not reaching the engine");
    }

    function test_longestSharedHandPaysItsShooterAfterTheirOwnBust() public {
        vm.warp(vm.getBlockTimestamp() + 10 days);
        _warpToDayStart();
        uint24 day = craps.currentDayIndex();
        craps.bookDay(day - 1, 3_000_000);
        _setDailyWord(day, PLAIN_WORD);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        uint256[3] memory ids;
        for (uint256 i; i < 3; ++i) {
            address player = address(uint160(100 + i));
            game.setScore(player, craps.SYBIL_SCORE_FLOOR());
            vm.prank(player);
            ids[i] = craps.enterBonusBattle(PER, _placed(i * 3), 1);
        }
        uint64 slot = uint64(uint256(day) * 8 + PER + 1);
        vm.warp(vm.getBlockTimestamp() + 7 hours);
        uint48 index = craps.armWindow(slot);
        uint256 n = craps.fieldCountOf(slot);
        uint256 best;
        uint256 hotId;
        bool found;
        for (uint256 k; k < 100; ++k) {
            _setWord(index, uint256(keccak256(abi.encode("busted-hot-shooter", k))));
            best = 0;
            for (uint256 i = 1; i <= n; ++i) {
                (CrapsBattle.Settlement memory receipt,) = craps.settlementForSeat(slot, i);
                uint256 candidate = receipt.hottestHand;
                if (candidate > best) best = candidate;
            }
            uint256 hand = 511 - (best & 511);
            uint256 start = uint256(keccak256(abi.encode(_ROTATION_TAG, craps.seedForBet(slot)))) % n;
            CrapsBattle.Settlement memory shooter;
            (shooter, hotId) = craps.settlementForSeat(slot, 1 + (start + hand) % n);
            if (shooter.stop == Craps.SlipStop.Bust && shooter.handsPlayed <= hand) {
                found = true;
                break;
            }
        }
        assertTrue(found, "fixture needs a longest hand after its shooter busted");
        vm.recordLogs();
        for (uint256 i; i < n; ++i) craps.settleSlot(slot, 1);
        assertEq(craps.longestOf(slot), best, "chunked shared record");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool paid;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("CrapsHottestShooterPaid(uint256,bytes32,address,uint16,uint256)")) {
                assertEq(uint256(logs[i].topics[1]), hotId);
                (uint16 rolls, uint256 amount) = abi.decode(logs[i].data, (uint16, uint256));
                assertEq(rolls, best >> 9);
                assertGt(amount, 0);
                paid = true;
            }
        }
        assertTrue(paid, "busted named shooter did not receive prize");
    }

    /// @dev A one-seat field: the start is seat one, hand zero is the turn, and that is all.
    function test_aLoneSeatShootsFirstAndOnlyOnce() public pure {
        bytes32 seed = keccak256("lone");
        assertEq(_turn(seed, 1, 1), 1 << 16, "a lone seat's turn is hand zero");
    }

    /// @dev Hands 0..N-1 name every seat exactly once, from any start, and wrap.
    function testFuzz_theFirstLapNamesEverySeatOnce(uint16 nRaw, bytes32 seed) public pure {
        uint256 n = 1 + (uint256(nRaw) % 600);
        uint256 start = 1 + uint256(keccak256(abi.encode(_ROTATION_TAG, seed))) % n;
        bool[] memory seen = new bool[](n);
        for (uint256 seat = 1; seat <= n; ++seat) {
            uint256 offset = (seat + n - start) % n;
            assertLt(offset, n, "offset out of range");
            assertFalse(seen[offset], "two seats share a hand");
            seen[offset] = true;
            assertEq(1 + ((start - 1 + offset) % n), seat, "shooterAt(offset) is not this seat");
            uint256 packed = _turn(seed, seat, n);
            if (offset >= 512) assertEq(packed, 0, "an unreachable turn must encode as none");
            else assertEq(packed >> 16, offset + 1, "the packed turn is off by one");
        }
    }

    /// @dev The engine and the oracle agree on rotation turns across the grid — including a turn
    ///      that goes hot (additive, floored once), a turn on the second lap
    ///      (never paid) and a turn past the run's stop (forfeited).
    function test_theRotationMatchesTheOracleOnEveryTurnAndOverlap() public view {
        Craps.Bets[3] memory boards;
        boards[0] = _mixed();
        boards[1] = _dark();
        boards[2].passLine = 240;
        boards[2].hard4 = 180;
        uint256[4] memory schedules = [uint256(0), _terms(12, 32), _terms(12, 32), _terms(12, 18)];
        uint256[6] memory turns = [uint256(0), 1, 2, 4, 9, 40];
        uint256 graded;
        uint256 lifted;
        for (uint256 i = 0; i < boards.length; ++i) {
            for (uint256 j = 0; j < schedules.length; ++j) {
                for (uint256 t = 0; t < turns.length; ++t) {
                    for (uint256 k = 0; k < 4; ++k) {
                        lifted += _gradeCell(boards[i], keccak256(abi.encode("rot-diff", i, j, t, k)), k, schedules[j], turns[t]);
                        ++graded;
                    }
                }
            }
        }
        assertEq(graded, 288, "grid");
        assertGt(lifted, 0, "no turn ever paid");
    }

    /// @dev One cell of the rotation differential: engine equals oracle; returns one when the
    ///      turn moved the money against the same schedule without it.
    function _gradeCell(Craps.Bets memory board, bytes32 seed, uint256 k, uint256 schedule, uint256 turn)
        internal
        view
        returns (uint256)
    {
        address who = k % 2 == 0 ? alice : bob;
        uint256 bank = 3000e18 * (1 + (k % 3));
        uint256 boost = schedule | (turn << 16);
        Craps.SlipResult memory got = craps.slip(board, seed, bank, bank * 10, 48, who, boost);
        CrapsOracle.SlipResult memory want = craps.oracle().resolveSlipBoosted(board, seed, bank, bank * 10, 48, who, boost);
        assertEq(got.bankrollOut, want.bankrollOut, "money");
        assertEq(got.handsPlayed, want.handsPlayed, "shooters");
        assertEq(got.totalRolls, want.totalRolls, "dice");
        assertEq(uint8(got.stop), uint8(want.stop), "stop");
        if (turn == 0) return 0;
        return got.bankrollOut != craps.slip(board, seed, bank, bank * 10, 48, who, schedule).bankrollOut ? 1 : 0;
    }

    function test_hotAndOwnShooterUseOnlyLateProfitAndOneFloor() public view {
        Craps.Bets memory board;
        board.place6 = 5;
        board.passLine = 5;
        uint256 differentFloors;
        for (uint256 k; k < 200; ++k) {
            bytes32 seed = keccak256(abi.encode("overlap", k));
            CrapsOracle.Outcome memory o = craps.oracle().resolveHand(board, craps.oracle().handSeed(seed, 0));
            uint256 combined = o.hotProfit * 60 / 100;
            if (combined != o.hotProfit * 30 / 100 + o.hotProfit * 30 / 100) ++differentFloors;
            Craps.SlipResult memory got = craps.slip(board, seed, 3000e18, 0, 1, alice, _terms(12, 30) | (1 << 16));
            assertEq(got.bankrollOut, 3000e18 - craps.stakeFor(board) + o.returned + combined, "bonus bases/floor");
        }
        assertGt(differentFloors, 0, "fixture must distinguish separate floors");
    }

    function _placed(uint256 placed) internal pure returns (Craps.Bets memory b) {
        b.passLine = uint24(placed > 3 ? 3 : placed);
        if (placed > 3) b.place6 = uint24(placed - 3 > 3 ? 3 : placed - 3);
        if (placed > 6) b.place8 = uint24(placed - 6);
    }

    /// @dev The board a bet actually PLAYS: its stored chips grown by the scatter, rebuilt here
    ///      off the same published inputs a client would use.
    function _scattered(uint256 betId, uint64 slot) internal view returns (Craps.Bets memory) {
        return craps.playedBoardOf(betId, slot);
    }

    /// @dev Open today's windows, seat a PICKED ticket and a BLANK one in period 1, shut it and
    ///      land a table word.
    function _openAndSeatBoth() internal returns (uint24 day, uint64 slot, uint48 index) {
        vm.warp(vm.getBlockTimestamp() + 10 days);
        _warpToDayStart();
        day = craps.currentDayIndex();
        craps.bookDay(day - 1, 3_000_000);
        _setDailyWord(day, PLAIN_WORD);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();

        vm.warp(vm.getBlockTimestamp() + 1 hours);
        vm.prank(alice);
        craps.enterBonusBattle(PER, _sevenChips(), 1);
        Craps.Bets memory blank;
        vm.prank(bob);
        craps.enterBonusBattle(PER, blank, 1);

        slot = uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + PER + 1);
        vm.warp(vm.getBlockTimestamp() + 7 hours);
        index = craps.armWindow(slot);
        _setWord(index, uint256(keccak256("boosted-table")));
    }

    function _warpToDayStart() internal {
        vm.warp(block.timestamp - ((block.timestamp - 82_620) % 1 days) + 1 days);
    }
}
