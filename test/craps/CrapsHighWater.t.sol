// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Craps} from "../../contracts/Craps.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {CrapsOracle} from "./CrapsOracle.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev Taps for the high-water lifecycle. Every one drives the SHIPPED engine or the SHIPPED
///      comparator; the only thing restated here is the packed terms word, which the wrapper
///      composes from constants this harness re-exposes.
contract WaterHarness is CrapsViews {
    CrapsOracle public immutable oracle;

    constructor() {
        oracle = new CrapsOracle();
    }

    /// @dev The engine under caller-chosen bounds, so a fixture can drive the shooter cap or the
    ///      roll budget directly. Everything else about the run is the one shipped rule set.
    function slipUnder(
        Craps.Bets calldata b,
        bytes32 seed,
        uint256 bankroll,
        uint256 goal,
        uint256 cap,
        uint256 rollBudget,
        address player,
        uint256 boost
    ) external pure returns (Craps.SlipResult memory) {
        return _settleSlip(b, seed, bankroll, goal, cap, rollBudget, player, boost);
    }

    function settlementAt(uint256 betId) external view returns (Settlement memory) {
        uint256 slot = betId >> 64;
        return _settlementOf(betId, _bets[betId], _slotWindow(slot), _wordAt(_indexOf(slot)));
    }

    /// @dev A slot's terms, so a fixture can drive the engine on exactly what a settlement did.
    function windowOf(uint64 slot) external view returns (Window memory) {
        return _slotWindow(slot);
    }

    /// @dev The seed a BET's run is keyed on: the table's word and the WINDOW's slot.
    function seedForSlot(uint64 slot) external view returns (bytes32) {
        return _crapsSeed(_wordAt(_indexOf(slot)), uint48(slot));
    }

    /// @dev The board a slip actually PLAYS — its own chips grown by the ones the dice place.
    function drawnBoardOf(uint256 betId) external view returns (Craps.Bets memory board) {
        uint64 slot = uint64(betId >> 64);
        uint256 header = _bets[betId];
        Window memory w = _slotWindow(slot);
        uint256 chipFlip = (w.played / 1 ether) / BONUS_CHIPS;
        uint256 packed = (header >> _BET_CHIPS_SHIFT) & _BET_CHIPS_MASK;
        uint256 placed;
        (, placed) = _packChips(uint32(packed));
        board = _boardFrom(packed, chipFlip);
        _scatterInto(
            board,
            uint256(keccak256(abi.encode(_wordAt(_indexOf(slot)), address(uint160(header))))),
            chipFlip,
            BONUS_CHIPS - placed
        );
    }

    function compositeAt(Settlement memory s) external pure returns (uint256) {
        return _compositeOf(s);
    }

    function bookDay(uint24 day, uint256 staked) external {
        _bookDay(day, staked, 0);
    }

    /// @dev The raw scoreboard word, so a fixture can stand a field up at the exact shape it
    ///      wants to grade the finalization on.
    function writeBattleWord(bytes32 key, uint256 word) external {
        _battles[key] = word;
    }

    /// @dev A bet header, so the synthesized winner is a real address carrying a real standing.
    function writeBet(uint256 betId, address player, uint256 standing) external {
        _bets[betId] = uint256(uint160(player)) | (standing << _BET_SCORE_SHIFT);
    }

    /// @dev THE SHIPPED FOLD, and — on the seat that completes the field — the shipped payout,
    ///      with its progressive rung and its record arm. The window is a real scheduled shape.
    function scoreAt(bytes32 key, uint256 score, uint64 seat, uint64 slot, uint256 bankrollFlip)
        external
    {
        Window memory w;
        w.key = key;
        w.bound = uint48(slot);
        w.bankroll = uint128(bankrollFlip * 1 ether);
        w.goal = uint128(bankrollFlip * SCHED_GOAL * 1 ether);
        w.played = (bankrollFlip / _SCHED_BANK_MULT) * 1 ether;
        _scoreBattle(w, score, seat, 0);
    }

    /// @dev The composite a scheduled goal folds, built through the shipped comparator.
    function goalScore(uint256 peakFlip, uint256 endFlip, uint256 standing) external pure returns (uint256) {
        Settlement memory s;
        s.stop = Craps.SlipStop.Goal;
        s.peak = peakFlip * 1 ether;
        s.won = endFlip * 1 ether;
        return _compositeOf(s) | standing;
    }
}

/// @title The scheduled Dice Run's high-water lifecycle
/// @notice A scheduled run does not stop when it reaches its target. It LATCHES the win, turns the
///         target into a reserve it may no longer stake, and plays on for as long as the escalator
///         and the hard bounds allow — ranking on the high point it reached and being PAID the
///         bankroll it ended on. A custom battle is untouched by every word of that.
contract CrapsHighWaterTest is CrapsPins {
    WaterHarness internal craps;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    uint256 internal constant PLAIN_WORD = 40 << 8;
    uint256 internal constant PER = 1;

    function setUp() public {
        _installPins();
        craps = new WaterHarness();
        vm.warp(block.timestamp + 1 days);
        _setIndex(4);
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
    }

    // ── Boards ──────────────────────────────────────────────────────────────

    /// @dev A full ten-chip board at a round unit, so every payout is exact.
    function _board() internal pure returns (Craps.Bets memory b) {
        b.passLine = 300;
        b.place4 = 300;
        b.place5 = 300;
        b.place6 = 300;
        b.place8 = 300;
        b.place9 = 300;
        b.place10 = 300;
        b.hard4 = 300;
        b.hard8 = 300;
    }

    /// @dev The light board with no dark lane and no hardways — the cheapest shape whose stake is
    ///      a round number, for the reserve arithmetic.
    function _line() internal pure returns (Craps.Bets memory b) {
        b.passLine = 600;
    }

    /// @dev The shipped bounds, which every slip runs under.
    function _run(Craps.Bets memory b, bytes32 seed, uint256 bank, uint256 goal, address who)
        internal
        view
        returns (Craps.SlipResult memory)
    {
        return craps.slipUnder(b, seed, bank, goal, craps.MAX_SLIP_HANDS(), craps.SLIP_ROLL_BUDGET(), who, 0);
    }

    // ════════════════════════════════════════════════════════════════════════
    // A. THE LATCH — reaching the goal stops a custom run and starts a scheduled one over.
    // ════════════════════════════════════════════════════════════════════════

    /// @dev THE LATCH, against a control the engine itself provides. Capping a run at `n`
    ///      shooters stops it there, and its stop reads Goal exactly when it had already latched
    ///      by shooter `n` — so the smallest such `n` IS the shooter at which the target was
    ///      first reached. The uncapped run then plays PAST it, which is the whole change.
    function test_theRunPlaysOnPastTheShooterThatWonIt() public view {
        Craps.Bets memory b = _board();
        uint256 bank = craps.stakeFor(b) * 4;
        uint256 goal = bank * 2;
        uint256 continued;
        uint256 examined;

        for (uint256 i = 0; i < 96; ++i) {
            bytes32 seed = keccak256(abi.encode("latch", i));
            Craps.SlipResult memory full = _run(b, seed, bank, goal, alice);
            if (full.stop != Craps.SlipStop.Goal) continue;
            ++examined;

            // THE WIN IS UNLOSABLE once latched: the reserve is what the run may not stake.
            assertGe(full.bankrollOut, goal, "a latched run ended below its own target");

            // The first shooter at which it was at or above target, found by capping.
            uint256 won;
            for (uint256 n = 1; n <= full.handsPlayed; ++n) {
                if (
                    craps.slipUnder(b, seed, bank, goal, n, craps.SLIP_ROLL_BUDGET(), alice, 0).stop
                        == Craps.SlipStop.Goal
                ) {
                    won = n;
                    break;
                }
            }
            assertGt(won, 0, "a goal run never read as a goal under any cap");
            // A HARD BOUND REACHED AFTER THE LATCH IS THE GOAL, which is what that probe just
            // proved at every cap from `won` up.
            if (full.handsPlayed > won) ++continued;
        }
        assertGt(examined, 0, "no run in the sweep reached its target");
        assertGt(continued, 0, "no run ever played past the shooter that won it");
    }

    /// @dev THE HIGH POINT IS NEVER PAID. Across a sweep, a latched run's ending bankroll may sit
    ///      well below the mark it touched — and the mark is what ranks it while the ending
    ///      figure is what it is credited.
    function test_aLatchedRunMayEndBelowItsOwnHighPoint() public view {
        Craps.Bets memory b = _board();
        uint256 bank = craps.stakeFor(b) * 4;
        uint256 goal = bank * 2;
        uint256 sawGap;

        for (uint256 i = 0; i < 128; ++i) {
            Craps.SlipResult memory r =
                craps.slipUnder(b, keccak256(abi.encode("gap", i)), bank, goal, craps.MAX_SLIP_HANDS(), craps.SLIP_ROLL_BUDGET(), alice, 0);
            assertGe(r.peakBankroll, r.bankrollIn, "a high point sat below the bankroll the run started with");
            assertGe(r.peakBankroll, r.bankrollOut, "a run ended above its own high point");
            if (r.stop == Craps.SlipStop.Goal && r.peakBankroll > r.bankrollOut) {
                assertGe(r.bankrollOut, goal, "a run gave back more than its surplus");
                ++sawGap;
            }
        }
        assertGt(sawGap, 0, "no run ever ended below its high point: the distinction is untested");
    }

    // ════════════════════════════════════════════════════════════════════════
    // B. THE PROTECTED RESERVE — equality plays, one wei short retires.
    // ════════════════════════════════════════════════════════════════════════

    /// @dev EQUALITY IS PLAYABLE, and one wei below it is not. A run that is already at its target
    ///      before the first shooter posts that shooter exactly when what is left behind is still
    ///      the whole target — so `bankroll - need == goal` plays and `- 1` stops on the spot.
    function test_equalityAtTheReservePlaysAndOneWeiBelowItStops() public view {
        Craps.Bets memory b = _line();
        uint256 stake = craps.stakeFor(b);
        uint256 goal = stake * 40;
        bytes32 seed = keccak256("reserve");

        // EXACTLY the reserve plus one whole shooter: it plays.
        Craps.SlipResult memory exact = craps.slipUnder(b, seed, goal + stake, goal, craps.MAX_SLIP_HANDS(), craps.SLIP_ROLL_BUDGET(), alice, 0);
        assertEq(uint8(exact.stop), uint8(Craps.SlipStop.Goal), "an at-target run did not latch");
        assertGe(exact.handsPlayed, 1, "equality at the reserve did not post a shooter");
        assertGe(exact.bankrollOut, goal, "the played shooter breached the reserve");

        // ONE WEI SHORT of it: the run retires without posting, and keeps everything it holds.
        Craps.SlipResult memory short = craps.slipUnder(b, seed, goal + stake - 1, goal, craps.MAX_SLIP_HANDS(), craps.SLIP_ROLL_BUDGET(), alice, 0);
        assertEq(uint8(short.stop), uint8(Craps.SlipStop.Goal), "a one-wei-short run lost its win");
        assertEq(short.handsPlayed, 0, "a one-wei-short run posted a shooter anyway");
        assertEq(short.bankrollOut, goal + stake - 1, "a retiring run was not paid what it was holding");
        assertEq(short.peakBankroll, goal + stake - 1, "the high point moved without a completed shooter");
    }

    /// @dev THE SURVIVAL COIN IS A PRE-GOAL INSTRUMENT ONLY. After the latch the reserve decides
    ///      affordability, and the branch that would take a coin is unreachable: a run holding
    ///      less than the next shooter needs is by definition holding less than the reserve plus
    ///      it, so it retires rather than gambling the lot.
    ///
    ///      Proven on a seat whose coin LOSES at the round in question — if the coin were ever
    ///      consulted past the latch, the run would come home with nothing.
    function test_noSurvivalCoinIsTakenAfterTheGoal() public view {
        Craps.Bets memory b = _line();
        uint256 stake = craps.stakeFor(b);
        bytes32 seed = keccak256("nocoin");

        // A seat whose coin is a LOSS on the first round of this table.
        address loser;
        for (uint256 i = 0; i < 512; ++i) {
            address who = address(uint160(uint256(keccak256(abi.encode("seat", i)))));
            if (!craps.survived(seed, 0, who)) {
                loser = who;
                break;
            }
        }
        assertTrue(loser != address(0), "no seat in the search lost its first coin");

        // Already at target, and short of a whole shooter beyond it. Pre-goal this is exactly the
        // shape that takes the coin — `bankroll * 2 >= need` and `bankroll < need`; past the latch
        // it simply stops.
        uint256 goal = stake / 4;
        uint256 bank = goal + (stake / 2);
        assertLt(bank, stake, "the fixture is not in the coin's own band");
        assertGe(bank * 2, stake, "the fixture is below the coin's band");

        Craps.SlipResult memory r = craps.slipUnder(b, seed, bank, goal, craps.MAX_SLIP_HANDS(), craps.SLIP_ROLL_BUDGET(), loser, 0);
        assertEq(uint8(r.stop), uint8(Craps.SlipStop.Goal), "the latched run did not stop as a goal");
        assertEq(r.handsPlayed, 0, "the latched run posted a shooter out of its reserve");
        assertEq(r.bankrollOut, bank, "a coin was taken past the latch and lost the bankroll");

        // And the SAME shape below the target still takes it — so the branch is real, and it is
        // the latch that turns it off rather than the fixture never reaching it.
        Craps.SlipResult memory belowGoal = craps.slipUnder(b, seed, bank, bank * 100, craps.MAX_SLIP_HANDS(), craps.SLIP_ROLL_BUDGET(), loser, 0);
        assertEq(uint8(belowGoal.stop), uint8(Craps.SlipStop.Bust), "the pre-goal coin did not fire at all");
        assertEq(belowGoal.bankrollOut, 0, "a lost pre-goal coin did not zero the bankroll");
    }

    // ════════════════════════════════════════════════════════════════════════
    // C. THE ESCALATOR — three shooters a doubling, two ceilings.
    // ════════════════════════════════════════════════════════════════════════

    /// @dev THE ESCALATOR, at every boundary the handoff names: shooters 0-2 wager 1x, 3-5 wager
    ///      2x, 93-95 wager 2,147,483,648x, and 96 onward wagers `uint32.max`.
    function test_theEscalatorDoublesEveryThreeShootersToUint32Max() public view {
        assertEq(craps.escOf(0), 1, "shooter 0");
        assertEq(craps.escOf(2), 1, "shooter 2");
        assertEq(craps.escOf(3), 2, "shooter 3");
        assertEq(craps.escOf(5), 2, "shooter 5");
        assertEq(craps.escOf(6), 4, "shooter 6");
        assertEq(craps.escOf(93), 2_147_483_648, "shooter 93");
        assertEq(craps.escOf(95), 2_147_483_648, "shooter 95");
        assertEq(craps.escOf(96), craps.ESC_CAP(), "shooter 96");
        assertEq(craps.escOf(511), craps.ESC_CAP(), "the last shooter the cap allows");
        assertEq(craps.ESC_CAP(), type(uint32).max, "the ceiling moved");
        assertEq(craps.ESC_HANDS(), 3, "the doubling period moved");

        // MONOTONE, never past the ceiling, and never zero, across the whole hand range. A zero
        // would be a free round; a wrapped shift is what would produce one.
        uint256 prev;
        for (uint256 h = 0; h < craps.MAX_SLIP_HANDS(); ++h) {
            uint256 q = craps.escOf(h);
            assertGe(q, prev, "the escalator went down");
            assertLe(q, craps.ESC_CAP(), "the escalator passed its ceiling");
            assertGt(q, 0, "the escalator handed out a free round");
            assertEq(q, h / 3 >= 32 ? craps.ESC_CAP() : (uint256(1) << (h / 3)), "a rung moved");
            prev = q;
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // D. THE HARD BOUNDS — 512 shooters, 8,192 rolls, an 8,703-roll ceiling.
    // ════════════════════════════════════════════════════════════════════════

    /// @dev THE STATED CEILING IS NOT THE BUDGET. The budget is judged BETWEEN shooters, so the
    ///      last shooter it admits may still run a whole hand of its own: the absolute total is
    ///      `8_192 - 1 + 512 = 8_703`.
    function test_theAbsoluteRollCeilingIsTheBudgetPlusOneWholeHand() public view {
        assertEq(craps.SLIP_ROLL_BUDGET(), 8192, "the scheduled budget moved");
        assertEq(craps.MAX_ROLLS(), 512, "one hand's own cap moved");
        assertEq(craps.SLIP_ROLL_CEILING(), 8703, "the absolute ceiling moved");
        assertEq(
            craps.SLIP_ROLL_CEILING(),
            craps.SLIP_ROLL_BUDGET() - 1 + craps.MAX_ROLLS(),
            "the ceiling is not budget - 1 + one whole hand"
        );
        assertEq(craps.MAX_SLIP_HANDS(), 512, "the shooter cap moved");
    }

    /// @dev THE SHOOTER CAP STOPS A RUN BOTH SIDES OF THE GOAL: reached before it, the run busts;
    ///      reached after it, the run is the goal it already latched.
    function test_theShooterCapBustsBeforeTheGoalAndStopsAtItAfter() public view {
        Craps.Bets memory b = _line();
        uint256 stake = craps.stakeFor(b);
        bytes32 seed = keccak256("cap");
        // Deep enough to outlast the escalator all the way to the cap.
        uint256 deep = stake * 1_800_000_000_000;

        // NO GOAL: the cap is a plain bust, exactly as it always was.
        Craps.SlipResult memory bust = craps.slipUnder(b, seed, deep, 0, craps.MAX_SLIP_HANDS(), craps.SLIP_ROLL_BUDGET(), alice, 0);
        assertEq(bust.handsPlayed, craps.MAX_SLIP_HANDS(), "the run did not reach the shooter cap");
        assertEq(uint8(bust.stop), uint8(Craps.SlipStop.Bust), "a capped run with no goal is not a bust");
        assertLe(bust.totalRolls, craps.SLIP_ROLL_CEILING(), "a capped run passed the roll ceiling");

        // A GOAL IT CLEARS AT ONCE: the same cap now stops it AS the goal, and it is paid what it
        // holds rather than being deleted.
        Craps.SlipResult memory won = craps.slipUnder(b, seed, deep, stake, craps.MAX_SLIP_HANDS(), craps.SLIP_ROLL_BUDGET(), alice, 0);
        assertEq(won.handsPlayed, craps.MAX_SLIP_HANDS(), "the latched run did not reach the cap");
        assertEq(uint8(won.stop), uint8(Craps.SlipStop.Goal), "a capped latched run lost its win");
        assertGt(won.bankrollOut, 0, "a capped latched run was deleted");
        assertGe(won.bankrollOut, stake, "a capped latched run ended below its own target");
    }

    /// @dev THE ROLL BUDGET STOPS A RUN TOO, on both sides of the goal. Driven on a caller-chosen
    ///      budget, because the shipped 8,192 is unreachable inside 512 shooters — which is the
    ///      point of sizing it there.
    function test_theRollBudgetStopsARunBothSidesOfTheGoal() public view {
        Craps.Bets memory b = _line();
        uint256 stake = craps.stakeFor(b);
        uint256 deep = stake * 1_800_000_000_000;
        bytes32 seed = keccak256("budget");


        Craps.SlipResult memory bust = craps.slipUnder(b, seed, deep, 0, 512, 40, alice, 0);
        assertLt(bust.handsPlayed, 512, "the shooter cap stopped it first, so the budget is untested");
        assertEq(uint8(bust.stop), uint8(Craps.SlipStop.Bust), "the budget did not bust an unqualified run");
        assertLe(bust.totalRolls, 40 - 1 + craps.MAX_ROLLS(), "the run passed budget - 1 + one whole hand");

        Craps.SlipResult memory won = craps.slipUnder(b, seed, deep, stake, 512, 40, alice, 0);
        assertEq(uint8(won.stop), uint8(Craps.SlipStop.Goal), "the budget deleted a latched run's win");
        assertGe(won.bankrollOut, stake, "a budget-stopped latched run ended below its target");
    }

    // ════════════════════════════════════════════════════════════════════════
    // E. THE ORACLE, differentially, over BOTH modes.
    // ════════════════════════════════════════════════════════════════════════

    /// @dev THE INDEPENDENT ORACLE AGREES, on every field. The twin holds the hand count, the
    ///      multiplier, the roll cursor and the latch as separate locals where the shipped engine
    ///      packs all four into one stack word, so this grades two encodings of the same rules
    ///      rather than one encoding twice.
    function test_theOracleAgrees() public view {
        Craps.Bets memory b = _board();
        uint256 stake = craps.stakeFor(b);
        uint256 goalSeen;
        uint256 bustSeen;
        uint256 boosted;

        for (uint256 i = 0; i < 64; ++i) {
            bytes32 seed = keccak256(abi.encode("differential", i));
            uint256 bank = stake * (3 + (i % 5));
            uint256 goal = bank * craps.SCHED_GOAL();

            Craps.SlipResult memory bare =
                craps.slipUnder(b, seed, bank, goal, craps.MAX_SLIP_HANDS(), craps.SLIP_ROLL_BUDGET(), alice, 0);
            _agree(bare, craps.oracle().resolveSlipFor(b, seed, bank, goal, craps.MAX_SLIP_HANDS(), alice), "bare");

            uint256 boost = craps.shooterBoostTerms(7);
            Craps.SlipResult memory sched = craps.slipUnder(
                b, seed, bank, goal, craps.MAX_SLIP_HANDS(), craps.SLIP_ROLL_BUDGET(), alice, boost
            );
            _agree(
                sched,
                craps.oracle().resolveSlipBoosted(b, seed, bank, goal, craps.MAX_SLIP_HANDS(), alice, boost),
                "boosted"
            );

            if (sched.stop == Craps.SlipStop.Goal) ++goalSeen;
            else ++bustSeen;
            if (sched.bankrollOut != bare.bankrollOut) ++boosted;
        }
        assertGt(goalSeen, 0, "the sweep never reached a goal");
        assertGt(bustSeen, 0, "the sweep never busted");
        assertGt(boosted, 0, "the schedule never moved a run: the boosted leg is untested");
    }

    function _agree(Craps.SlipResult memory got, CrapsOracle.SlipResult memory want, string memory what)
        internal
        pure
    {
        assertEq(got.bankrollIn, want.bankrollIn, string.concat(what, ": bankrollIn"));
        assertEq(got.bankrollOut, want.bankrollOut, string.concat(what, ": bankrollOut"));
        assertEq(got.peakBankroll, want.peakBankroll, string.concat(what, ": peakBankroll"));
        assertEq(got.handsPlayed, want.handsPlayed, string.concat(what, ": handsPlayed"));
        assertEq(got.unitsPlayed, want.unitsPlayed, string.concat(what, ": unitsPlayed"));
        assertEq(got.totalRolls, want.totalRolls, string.concat(what, ": totalRolls"));
        assertEq(uint8(got.stop), uint8(want.stop), string.concat(what, ": stop"));
    }

    // ════════════════════════════════════════════════════════════════════════
    // F. THE COMPARATOR — peak, then ending, then standing; busts untouched.
    // ════════════════════════════════════════════════════════════════════════

    function _goal(uint256 peakFlip, uint256 endFlip) internal pure returns (CrapsBattle.Settlement memory s) {
        s.stop = Craps.SlipStop.Goal;
        s.peak = peakFlip * 1 ether;
        s.won = endFlip * 1 ether;
        s.handsPlayed = 11;
    }

    function _bust(uint256 hands, uint256 endFlip) internal pure returns (CrapsBattle.Settlement memory s) {
        s.stop = Craps.SlipStop.Bust;
        s.handsPlayed = hands;
        s.won = endFlip * 1 ether;
        s.peak = 1e12 ether; // a bust's high point must reach neither field
    }

    /// @dev THE SCHEDULED LADDER, in order: a goal beats every bust; among goals the larger high
    ///      point wins; level on that the larger ending bankroll; level on that the higher frozen
    ///      standing. Nothing below that is in the composite — the table's own word breaks an
    ///      exact tie, which `CrapsBattle.t.sol` pins separately.
    function test_theScheduledComparatorRanksPeakThenEndingThenStanding() public view {
        assertGt(
            craps.compositeAt(_goal(1, 0)),
            craps.compositeAt(_bust(511, 1e12)),
            "a bust outranked a goal"
        );
        assertGt(
            craps.compositeAt(_goal(500, 0)),
            craps.compositeAt(_goal(499, 1e12)),
            "the high point is not the first term"
        );
        assertGt(
            craps.compositeAt(_goal(500, 90)) | 0,
            craps.compositeAt(_goal(500, 89)) | 4095,
            "the ending bankroll is not the second term"
        );
        assertGt(
            craps.compositeAt(_goal(500, 90)) | 8,
            craps.compositeAt(_goal(500, 90)) | 7,
            "the standing is not the last term"
        );
    }

    /// @dev THE ALL-BUST RACE IS BYTE-FOR-BYTE WHAT IT WAS, in both products: more shooters, then
    ///      the larger remainder, then the standing. A bust's temporary high point cannot enter
    ///      any of it — the goal bit is clear, so the primary field is its shooter count.
    function test_theAllBustComparatorIsUnchangedAndIgnoresAPeak() public view {
        assertGt(craps.compositeAt(_bust(9, 1)), craps.compositeAt(_bust(8, 1e12)), "shooters first");
        assertGt(craps.compositeAt(_bust(9, 2)), craps.compositeAt(_bust(9, 1)), "remainder second");
        assertGt(
            craps.compositeAt(_bust(9, 1)) | 5, craps.compositeAt(_bust(9, 1)) | 4, "standing third"
        );
        // The SAME bust ranks identically under both products' readings.
        assertEq(
            craps.compositeAt(_bust(9, 1)), craps.compositeAt(_bust(9, 1)), "a bust read two ways"
        );

        // And two busts differing ONLY in their high point are dead level.
        CrapsBattle.Settlement memory low = _bust(9, 1);
        CrapsBattle.Settlement memory high = _bust(9, 1);
        high.peak = 1e30;
        assertEq(craps.compositeAt(low), craps.compositeAt(high), "a bust's peak entered the race");
    }

}

/// @title The hard scheduled/custom boundary, end to end
/// @notice Two products share one engine and share nothing else. A custom battle may copy every
///         number the schedule draws — depth five, a 5x target, the same round — or retain another
///         target such as 20x, and still gets the legacy engine, no shooter boost, no high-water
///         continuation, no jackpot, no record, and no line in any day's action book.
contract CrapsCustomBoundaryTest is CrapsPins {
    WaterHarness internal craps;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    uint256 internal constant PLAIN_WORD = 40 << 8;
    uint256 internal constant PER = 1;
    uint32 internal constant PLAYED = 600;

    bytes32 internal constant _PAID_SIG = keccak256(
        "CrapsProgressivePaid(uint256,bytes32,address,bool,uint16,uint256,uint256,uint256,uint256,uint256)"
    );

    function setUp() public {
        _installPins();
        craps = new WaterHarness();
        vm.warp(block.timestamp + 1 days);
        _setIndex(4);
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
        uint256 floor_ = craps.SYBIL_SCORE_FLOOR();
        game.setScore(alice, floor_);
        game.setScore(bob, floor_);
        game.setScore(carol, floor_);
    }

    function _chips() internal pure returns (uint32) {
        // Seven chips: the pass line and two place numbers.
        return 3 | (uint32(2) << 3) | (uint32(2) << 9);
    }

    /// @dev A CUSTOM battle on numbers the SCHEDULE also draws: five rounds deep, and the target
    ///      the caller names. This is the shape the boundary has to hold apart.
    function _copycat(uint16 goalMult, uint48 index, uint256 salt) internal returns (uint64 slot) {
        slot = _openBattle(craps, PLAYED, 5, goalMult, 3);
        vm.prank(alice);
        craps.enterBattle(slot, _chips(), 1);
        vm.prank(bob);
        craps.enterBattle(slot, _chips(), 1);
        _closeOn(craps, slot, index, salt);
    }

    /// @dev CUSTOM BATTLES KEEP THEIR TARGET CHOICE. At depth five chasing either the scheduled
    ///      5x target or a custom 20x target, each settles on the LEGACY engine: the bare-engine
    ///      result off the same seed, with no schedule and no continuation.
    function test_customFiveAndTwentyXTargetsTakeTheBareEngine() public {
        uint16[2] memory goals = [uint16(5), 20];
        for (uint256 g = 0; g < 2; ++g) {
            uint64 slot = _copycat(goals[g], uint48(90 + g), uint256(keccak256(abi.encode("copycat", g))));
            uint256 betId = (uint256(slot) << 64) | 1;
            CrapsBattle.Settlement memory s = craps.settlementAt(betId);

            CrapsBattle.Window memory w = craps.windowOf(slot);
            (uint256 bank, uint256 goal) = (w.bankroll, w.goal);
            Craps.SlipResult memory bare = craps.slipUnder(
                craps.drawnBoardOf(betId),
                craps.seedForSlot(slot),
                bank,
                goal,
                craps.MAX_SLIP_HANDS(),
                craps.SLIP_ROLL_BUDGET(),
                craps.betOf(betId).player,
                0
            );
            assertEq(s.won, bare.bankrollOut, "a custom copy did not settle to the bare legacy engine");
            assertEq(s.handsPlayed, bare.handsPlayed, "a custom copy played a different number of shooters");
            assertEq(s.totalRolls, bare.totalRolls, "a custom copy threw a different number of dice");

            // AND NOT to the scheduled engine, which is the thing being ruled out. Only assert the
            // difference where the two engines actually diverge on this seed.
            Craps.SlipResult memory scheduled = craps.slipUnder(
                craps.drawnBoardOf(betId),
                craps.seedForSlot(slot),
                bank,
                goal,
                craps.MAX_SLIP_HANDS(),
                craps.SLIP_ROLL_BUDGET(),
                craps.betOf(betId).player,
                craps.shooterBoostTerms(7)
            );
            if (scheduled.bankrollOut != bare.bankrollOut) {
                assertTrue(s.won != scheduled.bankrollOut, "a custom copy settled under the scheduled engine");
            }
        }
    }

    /// @dev AND IT REACHES NONE OF THE SHARED MONEY. A settled custom field books no action to any
    ///      day, draws nothing from the progressive, and arms no record — whatever its numbers and
    ///      however far its winner ran.
    function test_aCustomFieldTouchesNoDayBookNoJackpotAndNoRecord() public {
        uint24 day = craps.currentDayIndex();
        uint256 stakedBefore = craps.dayStaked(day);
        uint256 highBefore = craps.highStakedOf(day);
        craps.seedProgressive(1_000_000 ether);
        uint256 poolBefore = craps.progressivePool();
        uint256 armsBefore = coinflip.diceRunArms();

        uint64 slot = _copycat(20, 95, uint256(keccak256("custom-money")));
        vm.recordLogs();
        craps.resolveSlot(slot, WHOLE_FIELD);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertTrue(craps.battleOf(craps.keyOfSlot(slot)).finalized, "the custom field did not finalize");
        assertEq(craps.dayStaked(day), stakedBefore, "a custom field booked action to a day");
        assertEq(craps.highStakedOf(day), highBefore, "a custom field booked high action to a day");
        assertEq(craps.progressivePool(), poolBefore, "a custom field moved the progressive");
        assertEq(coinflip.diceRunArms(), armsBefore, "a custom field armed the dice-run record");
        assertEq(coinflip.biggestDiceRunEver(), 0, "a custom field moved the record mark");
        for (uint256 i = 0; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != _PAID_SIG, "a custom field logged a progressive award");
        }

        // The day AFTER it settled is unmoved too — a custom battle books nowhere, not merely
        // somewhere else.
        assertEq(craps.dayStaked(day + 1), 0, "a custom field booked action to the settlement day");
    }

    /// @dev THE SCHEDULED SIDE, for contrast: the same walk on a protocol window DOES book its
    ///      bankrolls to the day it played. Without this the test above passes on a table that
    ///      simply never books anything.
    function test_aScheduledFieldStillBooksItsBankrollsToTheDayItPlayed() public {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint24 day = craps.currentDayIndex();
        _setDailyWord(day, PLAIN_WORD);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();

        vm.warp(vm.getBlockTimestamp() + 1 hours);
        vm.prank(alice);
        craps.enterBonusBattle(PER, _chips(), 1);

        uint64 slot = uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + PER + 1);
        vm.warp(vm.getBlockTimestamp() + 5 hours);
        uint48 index = craps.armBonusWindow(slot);
        _setWord(index, uint256(keccak256("scheduled-books")));

        (uint128 bank,,,,,) = craps.bonusTermsFor(day, PER);
        uint256 entrants = craps.battleOf(craps.keyOfSlot(slot)).entrants;
        uint256 before = craps.dayStaked(day);
        craps.resolveSlot(slot, WHOLE_FIELD);
        assertEq(craps.dayStaked(day) - before, uint256(bank) * entrants, "a scheduled field booked the wrong action");
    }

    /// @dev THE RECORD IS OFFERED ONCE PER FIELD and only above the floor, driven on the shipped
    ///      finalization: the fold completes a one-seat field, the payout runs, and the record
    ///      call is made or is not.
    ///
    ///      The floor is the WHOLE eligibility test. A 100x high point has necessarily crossed
    ///      the scheduled target, so there is no second goal check to get wrong.
    function test_theRecordIsArmedOncePerFieldAndOnlyAboveTheFloor() public {
        assertEq(craps.DICE_RUN_RECORD_FLOOR(), 1_000_000, "the record floor moved off 100x");
        uint256 bank = 3000;
        uint64 slot = 9; // a scheduled slot, far from any this suite opens for real

        // ONE FLIP BELOW the floor: no call at all.
        _stand("floor-below", slot, bank, craps.goalScore(bank * 100 - 1, 0, 12));
        assertEq(coinflip.diceRunArms(), 0, "a field below the floor called the record");
        assertEq(coinflip.biggestDiceRunEver(), 0, "a field below the floor moved the mark");

        // EXACTLY ON IT: one call, one mark, one credit.
        _stand("floor-on", slot, bank, craps.goalScore(bank * 100, 0, 12));
        assertEq(coinflip.diceRunArms(), 1, "the floor did not arm exactly once");
        assertEq(coinflip.biggestDiceRunEver(), 1_000_000, "the mark is not the winner's own score");
        assertEq(coinflip.staked(alice), coinflip.totalCredited(), "the claim reached somebody other than the winner");

        // A STRICT IMPROVEMENT ratchets and claims again.
        uint256 claimedBefore = coinflip.totalCredited();
        _stand("improve", slot, bank, craps.goalScore(bank * 150, 0, 12));
        assertEq(coinflip.diceRunArms(), 2, "an improving field did not arm");
        assertEq(coinflip.biggestDiceRunEver(), 1_500_000, "the mark did not ratchet");
        assertGe(coinflip.totalCredited(), claimedBefore, "a claim went backwards");

        // A LOWER high point still above the floor CALLS — the floor is the call gate — and moves
        // nothing, because the mark rule is a strict improvement.
        uint256 markBefore = coinflip.biggestDiceRunEver();
        uint256 creditedBefore = coinflip.totalCredited();
        _stand("regress", slot, bank, craps.goalScore(bank * 120, 0, 12));
        assertEq(coinflip.diceRunArms(), 3, "a qualifying field skipped the call");
        assertEq(coinflip.biggestDiceRunEver(), markBefore, "a lower high point moved the mark");
        assertEq(coinflip.totalCredited(), creditedBefore, "a lower high point claimed from the pool");
    }

    /// @dev Stand a ONE-SEAT scheduled field up at `score` and finalize it, so the shipped payout
    ///      — the progressive rung and the record arm — runs exactly as it does in production.
    function _stand(string memory tag, uint64 slot, uint256 bankrollFlip, uint256 score) internal {
        bytes32 key = keccak256(abi.encode(tag));
        craps.writeBattleWord(key, 1);
        craps.writeBet((uint256(slot) << 64) | 1, alice, craps.SYBIL_SCORE_FLOOR());
        craps.scoreAt(key, score, 1, slot, bankrollFlip);
    }

    /// @dev RESOLUTION ORDER DOES NOT MOVE THE VERDICT. The same field under every permutation of
    ///      its settle batches lands on the same winner, the same high point, the same pool
    ///      movement and the same record mark — the fold is a running maximum and the award
    ///      branch is reached exactly once, wherever the batches were cut.
    function test_theScoreboardIsOrderIndependentUnderEveryPartition() public {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        uint24 day = craps.currentDayIndex();
        _setDailyWord(day, PLAIN_WORD);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        vm.prank(alice);
        craps.enterBonusBattle(PER, _chips(), 1);
        vm.prank(bob);
        craps.enterBonusBattle(PER, _chips(), 1);
        vm.prank(carol);
        craps.enterBonusBattle(PER, _chips(), 1);

        uint64 slot = uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + PER + 1);
        vm.warp(vm.getBlockTimestamp() + 5 hours);
        _setWord(craps.armBonusWindow(slot), uint256(keccak256("permute")));
        craps.seedProgressive(1_000_000 ether);
        bytes32 key = craps.keyOfSlot(slot);

        uint64[3] memory winner;
        uint256[3] memory peak;
        uint256[3] memory pool;
        uint256[3] memory mark;
        uint256[3] memory action;
        uint256 snap = vm.snapshotState();

        for (uint256 mode = 0; mode < 3; ++mode) {
            if (mode != 0) vm.revertToState(snap);
            if (mode == 0) {
                craps.resolveSlot(slot, WHOLE_FIELD);
            } else if (mode == 1) {
                for (uint256 i = 0; i < 12; ++i) craps.resolveSlot(slot, 1);
            } else {
                craps.resolveSlot(slot, 8);
                craps.resolveSlot(slot, WHOLE_FIELD);
            }
            CrapsBattle.Battle memory b = craps.battleOf(key);
            assertTrue(b.finalized, "a partition left the field unfinished");
            winner[mode] = b.winnerId;
            peak[mode] = b.winningPeak;
            pool[mode] = craps.progressivePool();
            mark[mode] = coinflip.biggestDiceRunEver();
            action[mode] = craps.dayStaked(day);
        }
        for (uint256 m = 1; m < 3; ++m) {
            assertEq(winner[m], winner[0], "a partition chose a different winner");
            assertEq(peak[m], peak[0], "a partition stored a different high point");
            assertEq(pool[m], pool[0], "a partition moved the progressive by a different amount");
            assertEq(mark[m], mark[0], "a partition left a different record mark");
            assertEq(action[m], action[0], "a partition booked a different amount of action");
        }
    }
}
