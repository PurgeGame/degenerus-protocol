// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsOracle} from "./CrapsOracle.sol";

/// @title Craps resolver suite
/// @notice Two layers of oracle, doing different jobs.
///
///         The scripted-dice tests are the correctness net: every rule that has a right answer is
///         pinned against a hand-built dice sequence, so a wrong payout, a mis-ordered come-out, or
///         a bet that dies on the wrong roll fails deterministically and instantly.
///
///         The Monte Carlo test is the coverage net. Because the resolver is pure, a few hundred
///         thousand hands can be played inside one `eth_call` and the realised edge on every leg
///         compared against its closed form. It catches the class of bug that a scripted test
///         cannot: a rule that is subtly wrong in a state the script never visited.
contract CrapsTest is Test {
    CrapsOracle internal craps;

    /// @dev Stakes are whole FLIP; expectations are wei. 30 divides by 5, 6, and 2, so every
    ///      payout in the table lands exactly and no test result is contaminated by flooring.
    uint24 internal constant U = 30;
    uint256 internal constant UW = 30e18;

    /// @dev Scripted dice, built with `_r(d1, d2)` and consumed by `_play`.
    uint8[] internal _script;

    function setUp() public {
        craps = new CrapsOracle();
    }

    // ---------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------

    function _reset() internal {
        delete _script;
    }

    /// @dev Append one roll to the script.
    function _r(uint8 d1, uint8 d2) internal {
        _script.push(d1);
        _script.push(d2);
    }

    /// @dev All-zero bets. Every test turns on only the legs it is measuring.
    function _bets() internal pure returns (Craps.Bets memory b) {
        return b;
    }

    /// @dev Resolve the current script. The fallback seed is never reached: every script here ends
    ///      in a seven-out, which terminates the hand before the script runs out.
    function _play(Craps.Bets memory b) internal view returns (CrapsOracle.Outcome memory) {
        return craps.resolveHandWithScriptedDice(b, _script, bytes32(0));
    }

    // ---------------------------------------------------------------------------------------
    // Line bets and the point state machine
    // ---------------------------------------------------------------------------------------

    /// @dev The single most commonly botched rule: a 7 on the come-out is a pass-line WIN and the
    ///      shooter keeps rolling. It is not a seven-out. Only a 7 against an established point
    ///      ends the hand. The line pays and stays, so the 11 behind it pays AGAIN.
    function test_comeOutSevenIsNotASevenOut() public {
        _reset();
        _r(3, 4); // come-out 7  -> pass wins 1:1, stays up, hand continues
        _r(5, 6); // come-out 11 -> pass wins 1:1 again
        _r(2, 4); // point 6
        _r(3, 4); // seven-out -> the line's stake dies

        Craps.Bets memory b = _bets();
        b.passLine = U;

        CrapsOracle.Outcome memory o = _play(b);

        assertEq(o.rolls, 4, "hand ended on the come-out 7");
        assertFalse(o.truncated, "truncated");
        // Two 1:1 wins; the stake itself died on the seven-out. Dying once bounds the loss.
        assertEq(o.legReturned[craps.LEG_PASS()], UW * 2, "pass payout");
        assertEq(o.net, int256(UW), "net");
    }

    function test_comeOutElevenWinsPass() public {
        _reset();
        _r(5, 6); // come-out 11 -> wins 1:1, stays
        _r(2, 4); // point 6
        _r(3, 4); // seven-out -> stake dies

        Craps.Bets memory b = _bets();
        b.passLine = U;

        CrapsOracle.Outcome memory o = _play(b);
        assertEq(o.legReturned[craps.LEG_PASS()], UW, "one 1:1 win, stake died");
    }

    /// @dev With no dark side on the board there is no barred 12: every come-out craps number —
    ///      2, 3, AND 12 — simply loses the pass line.
    function test_everyComeOutCrapsNumberLosesPass() public {
        uint8[3] memory d1s = [1, 1, 6];
        uint8[3] memory d2s = [1, 2, 6];
        for (uint256 i = 0; i < 3; ++i) {
            _reset();
            _r(d1s[i], d2s[i]); // come-out 2 / 3 / 12
            _r(2, 4); // point 6
            _r(3, 4); // seven-out

            Craps.Bets memory b = _bets();
            b.passLine = U;

            CrapsOracle.Outcome memory o = _play(b);
            assertEq(o.legReturned[craps.LEG_PASS()], 0, "pass must lose");
            assertEq(o.net, -int256(UW), "net is the stake");
        }
    }

    function test_pointMadeWinsPassAndSevenOutEndsHand() public {
        _reset();
        _r(2, 4); // point 6
        _r(4, 5); // 9, nothing
        _r(3, 3); // 6 made -> pass wins 1:1 and stays
        _r(1, 4); // come-out 5 -> point 5
        _r(3, 4); // seven-out -> the line's stake dies

        Craps.Bets memory b = _bets();
        b.passLine = U;

        CrapsOracle.Outcome memory o = _play(b);

        assertEq(o.rolls, 5, "rolls");
        assertEq(o.legReturned[craps.LEG_PASS()], UW, "one point paid; the stake died riding");
        assertEq(o.pointsMade, 1, "points made");
    }

    /// @dev Points 4 and 10 still exist as POINTS even though they take no place bets, and the
    ///      distinct-points telemetry must count them.
    function test_pointsMadeCountsDistinctPointsOnly() public {
        _reset();
        _r(2, 4);
        _r(3, 3); // point 6 made (1st time)
        _r(2, 4);
        _r(3, 3); // point 6 made again -> still ONE distinct point
        _r(1, 3);
        _r(2, 2); // point 4 made -> a second distinct point, on a no-place-bet total
        _r(1, 4); // come-out 5 -> point 5, never made
        _r(3, 4); // seven-out

        CrapsOracle.Outcome memory o = _play(_bets());
        assertEq(o.pointsMade, 2, "distinct points");
    }

    // ---------------------------------------------------------------------------------------
    // Odds
    // ---------------------------------------------------------------------------------------

    /// @dev True odds: 2:1 on 4 and 10, 3:2 on 5 and 9, 6:5 on 6 and 8. Nothing shaded, which is
    ///      what makes the leg zero-edge.
    function test_passOddsPayTrueOddsOnThePoint() public {
        Craps.Bets memory b = _bets();
        b.passLine = U;
        b.passOddsMult = 2; // 2x the line, so a 2U odds stake

        _reset();
        _r(1, 3); // come-out 4 -> point 4, odds ride behind the line
        _r(2, 2); // 4 made -> pass wins 1:1, odds win 2:1; both stakes stay
        _r(1, 4); // come-out 5 -> point 5, the odds ride again
        _r(3, 4); // seven-out -> both stakes die riding
        CrapsOracle.Outcome memory four = _play(b);
        assertEq(four.legStaked[craps.LEG_PASS_ODDS()], UW * 2, "odds stake");
        assertEq(four.legReturned[craps.LEG_PASS()], UW, "pass 1:1");
        // 2:1 winnings on 2U; the stake itself died riding the 5.
        assertEq(four.legReturned[craps.LEG_PASS_ODDS()], UW * 4, "odds 2:1 on the 4");

        _reset();
        _r(2, 4); // point 6
        _r(3, 3); // 6 made -> odds win 6:5, stake stays
        _r(1, 4); // point 5
        _r(3, 4); // seven-out -> the odds stake dies riding
        CrapsOracle.Outcome memory six = _play(b);
        uint256 stake = UW * 2;
        assertEq(six.legReturned[craps.LEG_PASS_ODDS()], (stake * 6) / 5, "odds 6:5 on the 6");
    }

    function test_passOddsLoseOnTheSevenOut() public {
        Craps.Bets memory b = _bets();
        b.passLine = U;
        b.passOddsMult = 3;

        _reset();
        _r(1, 3); // point 4
        _r(3, 4); // seven-out
        CrapsOracle.Outcome memory o = _play(b);

        assertEq(o.legReturned[craps.LEG_PASS()], 0, "pass lost");
        assertEq(o.legReturned[craps.LEG_PASS_ODDS()], 0, "odds lost");
        assertEq(o.net, -int256(UW * 4), "line plus 3x odds");
    }

    /// @dev You cannot lose odds without a point. If the line dies on a come-out craps the odds
    ///      never rode anything, so the stake comes back untouched — this is what keeps the leg's
    ///      edge at exactly zero rather than merely close to it.
    function test_oddsAreRefundedWhenTheyNeverRide() public {
        Craps.Bets memory b = _bets();
        b.passLine = U;
        b.passOddsMult = 5;

        _reset();
        _r(1, 2); // come-out 3 -> the line craps out before any point exists
        _r(2, 4); // point 6, but the dead line arms nothing
        _r(3, 4); // seven-out
        CrapsOracle.Outcome memory o = _play(b);

        assertEq(o.legReturned[craps.LEG_PASS_ODDS()], UW * 5, "odds refunded in full");
        // The hand nets exactly the lost line stake: the odds leg is a wash.
        assertEq(o.net, -int256(UW), "odds contributed nothing either way");
    }

    /// @dev The odds ride every point established while the line lives, at true odds each cycle,
    ///      exactly like the line they sit behind.
    function test_oddsReArmOnEveryPointTheLineLives() public {
        Craps.Bets memory b = _bets();
        b.passLine = U;
        b.passOddsMult = 2;

        _reset();
        _r(1, 3); // point 4
        _r(2, 2); // 4 made -> pass 1:1, odds 2:1 winnings; both stakes stay
        _r(4, 6); // come-out 10 -> point 10, the odds ride again
        _r(5, 5); // 10 made -> pass 1:1 again, odds 2:1 again
        _r(1, 4); // point 5
        _r(3, 4); // seven-out -> both stakes die riding
        CrapsOracle.Outcome memory o = _play(b);

        // The 4 and the 10 were made; the 5 was only established before the seven-out.
        assertEq(o.pointsMade, 2, "two points made");
        assertEq(o.legReturned[craps.LEG_PASS()], UW * 2, "pass paid both points");
        assertEq(o.legReturned[craps.LEG_PASS_ODDS()], UW * 8, "odds paid 2:1 twice on 2U");
    }

    // ---------------------------------------------------------------------------------------
    // Place bets
    // ---------------------------------------------------------------------------------------

    /// @dev Pay-and-stay: each hit credits winnings only, the stake rides on, and the stake is lost
    ///      at the seven-out. That is what makes the leg's worst case exactly one stake.
    function test_placeSixPaysEveryHitThenDiesOnTheSeven() public {
        _reset();
        _r(1, 4); // come-out 5 -> point 5
        _r(2, 4); // 6 easy  -> pays 7:6
        _r(3, 3); // 6 hard  -> pays 7:6 again
        _r(3, 4); // seven-out -> stake lost

        Craps.Bets memory b = _bets();
        b.place6 = U;

        CrapsOracle.Outcome memory o = _play(b);

        uint256 leg = craps.LEG_PLACE() + craps.PLACE_6();
        assertEq(o.legReturned[leg], 2 * ((UW * 7) / 6), "two hits at 7:6");
        assertEq(o.legStaked[leg], UW, "stake");
        assertEq(o.net, int256(2 * ((UW * 7) / 6)) - int256(UW), "net");
    }

    function test_placePayoutTable() public {
        // One post-come-out hit on each number. 4/10 pay 9:5, 5/9 pay 7:5, 6/8 pay 7:6.
        _reset();
        _r(6, 6); // come-out 12 -> pass craps out; still the come-out, every place bet stays off
        _r(3, 3); // come-out 6 -> point 6 (a place 6 would not pay: still the come-out roll)
        _r(1, 3); // 4
        _r(1, 4); // 5
        _r(2, 6); // 8
        _r(4, 5); // 9
        _r(4, 6); // 10
        _r(2, 4); // 6 -> the point repeats, hand rolls on into a fresh come-out
        _r(1, 3); // come-out 4 -> point 4 (place 4 off, must not pay)
        _r(3, 4); // seven-out

        Craps.Bets memory b = _bets();
        b.place4 = U;
        b.place5 = U;
        b.place6 = U;
        b.place8 = U;
        b.place9 = U;
        b.place10 = U;

        CrapsOracle.Outcome memory o = _play(b);
        uint256 base = craps.LEG_PLACE();

        assertEq(o.legReturned[base + craps.PLACE_4()], (UW * 9) / 5, "place 4");
        assertEq(o.legReturned[base + craps.PLACE_5()], (UW * 7) / 5, "place 5");
        assertEq(o.legReturned[base + craps.PLACE_6()], (UW * 7) / 6, "place 6");
        assertEq(o.legReturned[base + craps.PLACE_8()], (UW * 7) / 6, "place 8");
        assertEq(o.legReturned[base + craps.PLACE_9()], (UW * 7) / 5, "place 9");
        assertEq(o.legReturned[base + craps.PLACE_10()], (UW * 9) / 5, "place 10");
    }

    function test_placeIsOffOnTheComeOut() public {
        _reset();
        _r(2, 4); // come-out 6 -> establishes the point AND would pay if working
        _r(3, 4); // seven-out

        Craps.Bets memory b = _bets();
        b.place6 = U;

        CrapsOracle.Outcome memory o = _play(b);
        assertEq(o.legReturned[craps.LEG_PLACE() + craps.PLACE_6()], 0, "no pay on the come-out");
    }

    /// @dev A place bet is off on the come-out, so a come-out seven cannot kill it and the shooter
    ///      rolls on with the bet intact.
    function test_placeSurvivesAComeOutSeven() public {
        Craps.Bets memory b = _bets();
        b.place6 = U;

        _reset();
        _r(3, 4); // come-out 7 -> pass would win; the place bet is off, so it is untouched
        _r(2, 4); // point 6
        _r(3, 3); // 6 -> pays, because the bet survived
        _r(1, 3); // come-out 4 -> point 4
        _r(3, 4); // seven-out

        CrapsOracle.Outcome memory o = _play(b);
        assertEq(o.rolls, 5, "hand continued past the come-out seven");
        assertEq(o.legReturned[craps.LEG_PLACE() + craps.PLACE_6()], (UW * 7) / 6, "survived and paid");
    }

    // ---------------------------------------------------------------------------------------
    // The hard eight
    // ---------------------------------------------------------------------------------------

    function test_hardEightPaysNineToOneAndDiesOnTheEasyWay() public {
        _reset();
        _r(1, 4); // come-out 5 -> point 5
        _r(4, 4); // hard 8 -> 9:1
        _r(4, 4); // hard 8 -> 9:1
        _r(2, 6); // easy 8 -> the bet dies
        _r(4, 4); // hard 8 -> nothing, it is already dead
        _r(3, 4); // seven-out

        Craps.Bets memory b = _bets();
        b.hard8 = U;

        CrapsOracle.Outcome memory o = _play(b);
        assertEq(o.legReturned[craps.LEG_HARD8()], UW * 18, "two hits at 9:1");
        assertEq(o.legStaked[craps.LEG_HARD8()], UW, "stake");
    }

    function test_hardFourPaysSevenToOneAndDiesOnTheEasyWay() public {
        _reset();
        _r(1, 4); // come-out 5 -> point 5
        _r(2, 2); // hard 4 -> 7:1
        _r(2, 2); // hard 4 -> 7:1
        _r(1, 3); // easy 4 -> the bet dies
        _r(2, 2); // hard 4 -> nothing, it is already dead
        _r(3, 4); // seven-out

        Craps.Bets memory b = _bets();
        b.hard4 = U;

        CrapsOracle.Outcome memory o = _play(b);
        assertEq(o.legReturned[craps.LEG_HARD4()], UW * 14, "two hits at 7:1");
        assertEq(o.legStaked[craps.LEG_HARD4()], UW, "stake");
    }

    /// @dev The hardways die independently: the easy 4 that kills the hard four is nothing to the
    ///      hard eight, which lives on to pay.
    function test_hardwaysLiveAndDieIndependently() public {
        _reset();
        _r(1, 4); // come-out 5 -> point 5
        _r(1, 3); // easy 4 -> hard four dies
        _r(4, 4); // hard 8 -> still pays 9:1
        _r(3, 4); // seven-out

        Craps.Bets memory b = _bets();
        b.hard4 = U;
        b.hard8 = U;

        CrapsOracle.Outcome memory o = _play(b);
        assertEq(o.legReturned[craps.LEG_HARD4()], 0, "hard four died");
        assertEq(o.legReturned[craps.LEG_HARD8()], UW * 9, "hard eight paid");
    }

    function test_hardEightIsOffOnTheComeOutAndSurvivesItsSeven() public {
        _reset();
        _r(3, 4); // come-out 7 -> the hard eight is off, untouched
        _r(1, 4); // point 5
        _r(4, 4); // hard 8 -> pays 9:1
        _r(3, 4); // seven-out

        Craps.Bets memory b = _bets();
        b.hard8 = U;

        CrapsOracle.Outcome memory o = _play(b);
        assertEq(o.legReturned[craps.LEG_HARD8()], UW * 9, "survived and paid");
    }

    // ---------------------------------------------------------------------------------------
    // Cross-bet interaction
    // ---------------------------------------------------------------------------------------

    /// @dev One roll can resolve several bets at once. A hard 8 that repeats the point pays the
    ///      pass line, the place 8, and the hard eight on the same roll.
    function test_oneRollCanPayThreeLegs() public {
        _reset();
        _r(2, 6); // come-out 8 -> point 8 (place and hardway are off on the come-out)
        _r(4, 4); // hard 8, and the point -> pass + place 8 + hard 8 all pay
        _r(1, 3); // come-out 4 -> point 4
        _r(3, 4); // seven-out

        Craps.Bets memory b = _bets();
        b.passLine = U;
        b.place8 = U;
        b.hard8 = U;

        CrapsOracle.Outcome memory o = _play(b);

        assertEq(o.legReturned[craps.LEG_PASS()], UW, "pass");
        assertEq(o.legReturned[craps.LEG_PLACE() + craps.PLACE_8()], (UW * 7) / 6, "place 8");
        assertEq(o.legReturned[craps.LEG_HARD8()], UW * 9, "hard 8");
    }

    // ---------------------------------------------------------------------------------------
    // Sessions
    // ---------------------------------------------------------------------------------------

    /// @dev A session must be exactly the same hands the single-hand entry point would produce.
    function test_sessionHandsMatchSingleHandReplay() public view {
        Craps.Bets memory b = _bets();
        b.passLine = U;
        b.place6 = U;
        b.hard8 = U;

        bytes32 seed = keccak256("session");
        uint256 hands = 32;

        CrapsOracle.Session memory s = craps.resolveHands(b, seed, hands);
        assertEq(s.hands, hands, "hands");
        assertEq(s.ledger.length, hands, "ledger length");

        int256 sumNet;
        uint256 sumRolls;
        for (uint256 i = 0; i < hands; ++i) {
            CrapsOracle.Outcome memory o = craps.resolveHand(b, craps.handSeed(seed, i));
            assertEq(s.ledger[i].net, o.net, "ledger net");
            assertEq(s.ledger[i].rolls, o.rolls, "ledger rolls");
            assertEq(s.ledger[i].pointsMade, o.pointsMade, "ledger points");
            assertFalse(s.ledger[i].truncated, "ledger truncated");
            sumNet += o.net;
            sumRolls += o.rolls;
        }
        assertEq(s.net, sumNet, "session net");
        assertEq(s.totalRolls, sumRolls, "session rolls");
    }

    function test_sessionChargeIsStakeTimesHands() public view {
        Craps.Bets memory b = _bets();
        b.passLine = U;
        b.place6 = U;

        CrapsOracle.Outcome memory one = craps.resolveHand(b, craps.handSeed(bytes32(uint256(1)), 0));
        CrapsOracle.Session memory s = craps.resolveHands(b, bytes32(uint256(1)), 100);

        assertEq(s.staked, one.staked * 100, "upfront charge");
        assertGe(s.net, -int256(s.staked), "lost more than the session stake");
    }

    function test_sessionAndSimulateAgree() public view {
        Craps.Bets memory b = _bets();
        b.passLine = U;
        b.place9 = U;

        bytes32 seed = keccak256("agree");
        CrapsOracle.Session memory s = craps.resolveHands(b, seed, 64);
        CrapsOracle.Sim memory sim = craps.simulate(b, seed, 64);

        assertEq(sim.staked, s.staked, "staked");
        assertEq(sim.returned, s.returned, "returned");
        assertEq(sim.totalRolls, s.totalRolls, "rolls");
        for (uint256 k = 0; k < 10; ++k) {
            assertEq(sim.legReturned[k], s.legReturned[k], "leg");
        }
    }

    function test_sessionRejectsOutOfRangeHandCounts() public {
        Craps.Bets memory b = _bets();
        b.passLine = U;

        // Hoisted deliberately: `craps.MAX_SESSION_HANDS()` is itself an external call, and left
        // inline it becomes the "next call" that expectRevert latches onto instead of the one
        // under test.
        uint256 tooMany = craps.MAX_SESSION_HANDS() + 1;

        vm.expectRevert(CrapsOracle.BadHandCount.selector);
        craps.resolveHands(b, bytes32(0), 0);

        vm.expectRevert(CrapsOracle.BadHandCount.selector);
        craps.resolveHands(b, bytes32(0), tooMany);
    }

    // ---------------------------------------------------------------------------------------
    // Invariants
    // ---------------------------------------------------------------------------------------

    /// @dev The property the whole bet set was chosen for: a hand can never cost the player more
    ///      than the stakes they put down, so `Outcome.staked` is the exact escrow requirement and
    ///      no upfront liability formula is needed anywhere.
    function testFuzz_lossIsBoundedByTheStake(uint256 seed, uint24 rawStake) public view {
        uint24 s = uint24(bound(uint256(rawStake), 1, 16_777_215));

        Craps.Bets memory b = _bets();
        b.passLine = s;
        b.place4 = s;
        b.place5 = s;
        b.place6 = s;
        b.place8 = s;
        b.place9 = s;
        b.place10 = s;
        b.hard4 = s;
        b.hard8 = s;
        b.passOddsMult = 2;

        CrapsOracle.Outcome memory o = craps.resolveHand(b, bytes32(seed));

        assertGe(o.net, -int256(o.staked), "lost more than the stake");
        // 9 flat legs plus 2x odds behind the line, all in wei.
        assertEq(o.staked, uint256(s) * 11 * 1e18, "stake vector");
        // The escrow's charge and the resolver's own count are two functions; pin them together.
        assertEq(craps.stakeFor(b), o.staked, "stakeFor != resolver staked");

        uint256 sumStaked;
        uint256 sumReturned;
        for (uint256 k = 0; k < 10; ++k) {
            sumStaked += o.legStaked[k];
            sumReturned += o.legReturned[k];
        }
        assertEq(sumStaked, o.staked, "staked total");
        assertEq(sumReturned, o.returned, "returned total");
        assertEq(o.net, int256(o.returned) - int256(o.staked), "net");
    }

    /// @dev Every hand must terminate in a seven-out well inside the cap.
    function testFuzz_handAlwaysTerminates(uint256 seed) public view {
        Craps.Bets memory b = _bets();
        b.passLine = U;
        CrapsOracle.Outcome memory o = craps.resolveHand(b, bytes32(seed));
        assertFalse(o.truncated, "hit MAX_ROLLS");
        assertGt(o.rolls, 0, "no rolls");
    }

    /// @dev `handDice` re-walks the point machine separately from `_run`, so the two could drift
    ///      and start disagreeing about what the shooter rolled. This pins them.
    function testFuzz_publishedDiceAreTheSettledHand(uint256 seed) public view {
        Craps.Bets memory b = _bets();
        b.passLine = U;
        b.place6 = U;

        CrapsOracle.Outcome memory o = craps.resolveHand(b, bytes32(seed));
        uint8[] memory dice = craps.handDice(bytes32(seed));

        assertEq(dice.length % 2, 0, "dice are not whole pairs");
        assertEq(dice.length / 2, o.rolls, "published roll count != settled roll count");

        for (uint256 i = 0; i < dice.length; ++i) {
            assertGe(dice[i], 1, "die below 1");
            assertLe(dice[i], 6, "die above 6");
        }

        // Every hand here ends on a seven-out, and only the last roll may be that seven.
        uint256 last = dice.length - 2;
        assertEq(uint256(dice[last]) + uint256(dice[last + 1]), 7, "hand did not end on a seven");
    }

    // ---------------------------------------------------------------------------------------
    // Dice
    // ---------------------------------------------------------------------------------------

    /// @dev Reducing an 8-bit draw mod 6 would give four faces 43/256 and two faces 42/256 — a
    ///      2.4% relative skew, larger than the entire pass-line edge. The 32-bit reduction the
    ///      contract actually uses is off by ~1e-9.
    function test_diceAreUniform() public view {
        uint256 n = 200_000;
        uint256[7] memory faces;
        uint256[13] memory totals;

        for (uint256 i = 0; i < n; ++i) {
            (uint256 d1, uint256 d2) = craps.diceAt(bytes32(uint256(0xD1CE)), i);
            ++faces[d1];
            ++faces[d2];
            ++totals[d1 + d2];
        }

        uint256 expectedFace = (2 * n) / 6;
        for (uint256 f = 1; f <= 6; ++f) {
            assertApproxEqRel(faces[f], expectedFace, 0.015e18, "face frequency");
        }

        // Totals must follow the 1/36 weights, which also catches the two lanes being correlated.
        uint8[13] memory ways = [0, 0, 1, 2, 3, 4, 5, 6, 5, 4, 3, 2, 1];
        for (uint256 t = 2; t <= 12; ++t) {
            assertApproxEqRel(totals[t], (n * ways[t]) / 36, 0.05e18, "total frequency");
        }
    }

    // ---------------------------------------------------------------------------------------
    // House edge
    // ---------------------------------------------------------------------------------------

    /// @dev Plays the whole board over many hands and checks each leg's realised edge against its
    ///      closed form. Targets, in parts per million of the stake, for the ride-to-the-seven-out
    ///      model this contract implements:
    ///
    ///        pass        -7/251    = -27888   (pay-and-stay: ~1.97 decisions at the textbook
    ///                                          1.41% each before the stake dies)
    ///        odds        exactly 0
    ///        place 4/10  -1/10     = -100000  place 5/9 -1/15 = -66667  place 6/8 -1/36 = -27778
    ///        hard 4      -1/8      = -125000  hard 8    -1/10 = -100000
    ///
    ///      The place and hardway figures are per STAKE for a bet riding until the 7, not the
    ///      per-decision numbers casinos quote. Both describe the same bet.
    ///
    ///      Default 200k hands. Crank CRAPS_HANDS and the tolerances tighten automatically.
    function test_houseEdgeConverges() public {
        uint256 hands = vm.envOr("CRAPS_HANDS", uint256(200_000));

        Craps.Bets memory b = _bets();
        b.passLine = U;
        b.place4 = U;
        b.place5 = U;
        b.place6 = U;
        b.place8 = U;
        b.place9 = U;
        b.place10 = U;
        b.hard4 = U;
        b.hard8 = U;
        b.passOddsMult = 2;

        CrapsOracle.Sim memory s = craps.simulate(b, keccak256("craps"), hands);

        assertEq(s.truncatedHands, 0, "a hand hit MAX_ROLLS");
        // Mean hand length is 8.53 rolls — a hard number, and the cheapest possible smoke test on
        // the point machine and the dice at once.
        assertApproxEqAbs((s.totalRolls * 100) / hands, 853, 15, "mean hand length x100");

        int256[10] memory target;
        // Per-hand standard deviation of each leg's net, x1000, used to size the tolerance.
        uint256[10] memory sdMilli;
        string[10] memory name;

        (target[0], sdMilli[0], name[0]) = (-27888, 1385, "pass      ");
        // The odds leg is exactly zero-edge by construction, which makes it the sharpest assertion
        // in this table: any error in the true-odds ratios shows up with nothing to hide behind.
        (target[1], sdMilli[1], name[1]) = (0, 1500, "pass odds ");
        (target[2], sdMilli[2], name[2]) = (-100000, 1560, "place 4   ");
        (target[3], sdMilli[3], name[3]) = (-66667, 1480, "place 5   ");
        (target[4], sdMilli[4], name[4]) = (-27778, 1440, "place 6   ");
        (target[5], sdMilli[5], name[5]) = (-27778, 1440, "place 8   ");
        (target[6], sdMilli[6], name[6]) = (-66667, 1480, "place 9   ");
        (target[7], sdMilli[7], name[7]) = (-100000, 1560, "place 10  ");
        (target[8], sdMilli[8], name[8]) = (-125000, 2630, "hard 4    ");
        (target[9], sdMilli[9], name[9]) = (-100000, 2980, "hard 8    ");

        uint256 rootN = _sqrt(hands);

        for (uint256 k = 0; k < 10; ++k) {
            int256 edge =
                ((int256(s.legReturned[k]) - int256(s.legStaked[k])) * 1e6) / int256(s.legStaked[k]);

            // 4 sigma of the mean, in ppm of the stake.
            uint256 tol = (4 * sdMilli[k] * 1000) / rootN;
            emit log_named_string(
                name[k],
                string.concat(
                    vm.toString(edge),
                    " ppm  target ",
                    vm.toString(target[k]),
                    "  tol +/-",
                    vm.toString(tol)
                )
            );
            assertApproxEqAbs(edge, target[k], tol, name[k]);
        }
    }

    function _sqrt(uint256 x) private pure returns (uint256 y) {
        if (x == 0) return 0;
        y = x;
        uint256 z = x / 2 + 1;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
