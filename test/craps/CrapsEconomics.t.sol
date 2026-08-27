// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsViews} from "./CrapsViews.sol";
import {Test} from "forge-std/Test.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsOracle} from "./CrapsOracle.sol";
import {LootboxCraps} from "../../contracts/LootboxCraps.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {CrapsBattle, IFlipCoin, ICoinflipStake} from "../../contracts/CrapsBattle.sol";

contract EconHarness is CrapsViews {
    /// @dev The theo cross-check grades production's lean settlement against an independent
    ///      engine off the same seed. `resolveSlipAt` was cut from production (EIP-170; the paying
    ///      path never called it), so it is rebuilt here over the SHIPPED `seedFor`.
    CrapsOracle internal immutable oracle;

    constructor() {
        oracle = new CrapsOracle();
    }

    /// @dev The board a slip actually PLAYS: its seven chips grown by the three the dice place.
    ///      Both the oracle cross-check and the theo have to be taken against this, never against
    ///      the counts the ticket named.
    function drawnBoardOf(uint256 betId) external view returns (Craps.Bets memory board) {
        uint256 header = _bets[betId];
        Window memory w = _slotWindow(betId >> 64);
        uint256 chipFlip = (w.played / 1 ether) / BONUS_CHIPS;
        uint256 packed = (header >> _BET_CHIPS_SHIFT) & _BET_CHIPS_MASK;
        uint256 thrown = BONUS_CHIPS;
        if (packed != 0) {
            board = _boardFrom(packed, chipFlip);
            thrown = _RSEL_PICK7;
        }
        _scatterInto(
            board,
            uint256(keccak256(abi.encode(_wordAt(_indexOf(betId >> 64)), address(uint160(header))))),
            chipFlip,
            thrown
        );
    }

    /// @dev The whole settlement of a bet, stop included — production decides a FORFEIT off the
    ///      stop, so a suite grading the money path has to be able to see it.
    function settlementAt(uint256 betId) external view returns (Settlement memory) {
        return _settlementOf(betId, _bets[betId], _slotWindow(betId >> 64), _wordAt(_indexOf(betId >> 64)));
    }

    /// @dev Engine-only: a run off a bare table seed, for comparisons that hold no bet.
    function resolveSlipAt(Craps.Bets calldata b, uint48 index, uint256 bankroll, uint256 goal, uint256 cap)
        external
        view
        returns (CrapsOracle.SlipResult memory)
    {
        return oracle.resolveSlip(b, _seedFor(index), bankroll, goal, cap);
    }

    /// @dev Seeded the way PRODUCTION seeds a BET: `_crapsSeed(word, slot)`. A settlement keys its
    ///      run on the battle's slot, not on the table index it shut onto — two slots that took
    ///      the same table still get their own dice — so an oracle keyed on the index could never
    ///      agree with it. The OWNER rides in beside it because the survival coin is salted by the
    ///      slip's owner: an oracle that left it out would diverge the moment a coin fired.
    function resolveSlipForBet(
        Craps.Bets calldata b,
        uint64 slot,
        uint256 bankroll,
        uint256 goal,
        uint256 cap,
        address player
    ) external view returns (CrapsOracle.SlipResult memory) {
        return oracle.resolveSlipFor(
            b, _crapsSeed(_wordAt(_indexOf(slot)), uint48(slot)), bankroll, goal, cap, player
        );
    }
}

/// @title Craps economic invariant — can this table print FLIP?
///
/// @notice FLIP has no reserve behind it: a losing wager BURNS and a winning one MINTS. So the
///         question is not whether a house bankroll survives, it is whether the expected mint
///         comes to less than the burn at every round, depth and target a battle may be opened on.
///
/// @dev THE ARGUMENT CHANGED WITH THE PAYOUT TABLE. It used to run:
///
///        burn      = bankroll                          (taken at placement, in full)
///        E[mint]   = bankroll - (the house edge)       every leg carries one, none is zero-edge
///        =>  E[mint] < burn
///
///      The middle line is now FALSE. Place 4/10 pay 2:1 and place 5/9 pay 3:2, which are the
///      exact true odds of those bets in this ride-to-the-seven-out model, so those four legs
///      carry NO edge at all. A ticket may name every chip it picks on them, and the dice may
///      scatter the rest there too — so a legal board can be a fair game end to end, and the
///      per-leg edge is no longer a floor under anything.
///
///      What holds instead, and holds on EVERY board including a fair one:
///
///        burn        = bankroll                        (taken at placement, in full)
///        E[won]      <= bankroll                       fair legs are a martingale; the rest bleed
///        E[paid]     = E[won x 1{goal}] < E[won]       A BUST PAYS NOTHING AND IS DELETED
///        =>  E[mint] < burn
///
///      The deletion is what does the work now. A run that goes broke chasing its target hands
///      back nothing — not to the player, not to the winner, not to any pot — so whatever it was
///      still holding is simply never re-minted. That is a strictly positive take on every board
///      the table can be dealt, fair legs and all.
///
///      The per-leg edges are pinned by `test_houseEdgeConverges` over 200k hands at 4 sigma in
///      `Craps.t.sol`, the four zeroes included. What is checked HERE is the composition — that a
///      real run, settled by the shipped path with its rounding and its deletion, still comes home
///      short of what it burned.
///
///      Deliberately NOT asserted: a tight match between realised loss and any closed form. Per
///      unit, realised loss has a standard deviation on the order of the stake itself against a
///      mean of a few percent of it, so at any sample size this suite can afford, such an
///      assertion would be measuring noise.
contract CrapsEconomicsTest is CrapsPins {
    EconHarness internal craps;

    address internal player = makeAddr("player");

    function setUp() public {
        _installPins();
        craps = new EconHarness();
        // Worst case for the protocol: every comp pays the 75% ceiling.
        game.setScore(player, 65_534);
    }

    function _ids(uint64 a) internal pure returns (uint64[] memory out) {
        out = new uint64[](1);
        out[0] = a;
    }

    /// @dev Boards spanning the whole shape of the game: the grind, the bleeders, the
    ///      indulgences, a pure ZERO-EDGE true-odds board, and as much as one entry can light at
    ///      once. All of them are seven whole chips, since that is the only shape a door takes.
    /// @dev The round every fixture here plays, in whole FLIP: ten chips of a hundred.
    uint32 internal constant PLAYED = 1000;

    /// @dev Boards are chip COUNTS now — seven of the round's ten, wherever they go. The shapes
    ///      keep the leg proportions the theo argument was written against.
    function _board(uint256 which) internal pure returns (Craps.Bets memory b) {
        if (which == 0) {
            b.passLine = 4;
            b.place6 = 3;
        } else if (which == 1) {
            b.passLine = 2;
            b.place6 = 2;
            b.place8 = 3;
        } else if (which == 2) {
            // THE FAIR BOARD: true odds end to end, expected loss exactly zero on every leg.
            b.place4 = 4;
            b.place10 = 3;
        } else if (which == 3) {
            b.hard4 = 4;
            b.hard8 = 3;
        } else {
            // As many legs as seven chips can light, with the pass line carrying two.
            b.passLine = 2;
            b.place4 = 1;
            b.place5 = 1;
            b.place6 = 1;
            b.place8 = 1;
            b.place9 = 1;
        }
    }

    /// @dev One table, one battle: open it on these terms, seat the player, shut it onto `idx`
    ///      and land `word`. The whole lifecycle a single-entrant fixture needs.
    function _run(Craps.Bets memory chips, uint8 bankMult, uint16 goalMult, uint48 idx, uint256 word)
        internal
        returns (uint256 betId, uint64 slot)
    {
        slot = _openBattle(craps, PLAYED, bankMult, goalMult, 0);
        vm.prank(player);
        betId = craps.enterBattle(slot, chips, 1);
        _closeOn(craps, slot, idx, word);
    }

    /// @notice STEP 2: over many independent goal runs the REALISED credit — every rounding roll
    ///         included — must land on their summed pre-rounding `won`. Bust remainders are
    ///         intentionally forfeited and therefore excluded from this rounding check.
    function test_theRoundingIsEvNeutralInAggregate() public {
        Craps.Bets memory b = _board(5);
        uint8 bankMult = 4;
        // A take-profit goal (the battle floor) bounds each run's final figure. Without one, the
        // mid-run second chance's repeated double-or-nothing gives `won` a St. Petersburg tail —
        // each survived double halves the odds — whose mean is dominated by rare deep doublings:
        // EV-neutral (proven exactly by the Wald argument) but far too heavy-tailed for a
        // realised-vs-expected mean to converge at any affordable sample size. Capping the run
        // makes this rounding check measurable, and the doubling coin is still exercised hard —
        // a survive is the usual way a run reaches the stop.
        uint16 goalMult = uint16(craps.MIN_BATTLE_GOAL_MULT());

        uint256 expectedWon;
        uint256 expectedCredit;
        uint256 n = 400;

        for (uint256 i = 0; i < n; ++i) {
            (uint256 betId, uint64 slot) =
                _run(b, bankMult, goalMult, uint48(20_000 + i), uint256(keccak256(abi.encode("flipev", i))));
            (uint256 won, uint256 paid) = craps.previewSettlement(betId);
            if (paid != 0) expectedWon += won;
            expectedCredit += paid;
            craps.resolveSlot(slot, WHOLE_FIELD);
        }

        emit log_named_uint("goal returns    ", expectedWon);
        emit log_named_uint("expected credit ", expectedCredit);
        emit log_named_uint("realised credit ", coinflip.totalCredited());

        // Centred, not shaded upward: the rounding granule is tiny against 800 runs, so the two
        // totals sit almost exactly on each other.
        assertGt(expectedWon, 0, "no goal run came home");
        assertEq(coinflip.totalCredited(), expectedCredit, "previewed credit != realised credit");
        assertApproxEqRel(coinflip.totalCredited(), expectedWon, 0.02e18, "rounding drifted from goal returns");
        // A run's winnings are CREDIT, never a mint: only an uncontested bounty refund mints.
        assertEq(flip.totalMinted(), 0, "a run's winnings minted liquid FLIP");
    }

    /// @notice The whole loop, end to end, on an EDGE-BEARING board: burn at placement, run the
    ///         shipped engine, credit the award. What is ASSERTED is the well-powered half — that
    ///         what actually mints falls short of what was burned. The size of the residual is
    ///         REPORTED rather than asserted, because a sample this size can land either way
    ///         without saying anything about the expectation.
    function test_theTableIsANetBurn() public {
        Craps.Bets memory b = _board(4);
        uint8 bankMult = 4;
        uint256 bankroll = uint256(PLAYED) * bankMult * 1 ether;
        // A REACHABLE target, so runs actually come home and the mint is a real number rather
        // than the trivial zero an unreachable goal produces.
        uint16 goalMult = uint16(craps.MIN_BATTLE_GOAL_MULT());

        uint256 burned;
        uint256 rawWon;
        uint256 units;
        uint256 creditedBefore = coinflip.totalCredited();

        for (uint256 i = 0; i < 600; ++i) {
            uint48 idx = uint48(30_000 + i);
            (uint256 betId, uint64 slot) =
                _run(b, bankMult, goalMult, idx, uint256(keccak256(abi.encode("netburn", i))));

            Craps.Bets memory drawn = craps.drawnBoardOf(betId);
            CrapsOracle.SlipResult memory r = craps.resolveSlipForBet(drawn, slot, bankroll, uint256(bankroll) * goalMult, craps.MAX_SLIP_HANDS(), craps.betOf(betId).player);
            (uint256 won,) = craps.previewSettlement(betId);
            craps.resolveSlot(slot, WHOLE_FIELD);

            burned += bankroll;
            rawWon += won;
            units += r.unitsPlayed;
        }
        uint256 minted = coinflip.totalCredited() - creditedBefore;

        emit log_named_uint("burned          ", burned);
        emit log_named_uint("raw won         ", rawWon);
        emit log_named_uint("actually minted ", minted);
        emit log_named_uint("units wagered   ", units);

        // ASSERTED: what the table gives back is less than what it took. `minted` is the real
        // figure — every busted run contributed exactly zero to it.
        assertLt(minted, burned, "the mint exceeded the burn");
        // And a run's winnings are CREDIT, never a mint: only an uncontested bounty refund mints.
        assertEq(flip.totalMinted(), 0, "a run's winnings minted liquid FLIP");

        // REPORTED: the residual, signed, because a sample this size can land either way without
        // saying anything about the expectation.
        emit log_named_int("net burn (signed)", int256(burned) - int256(minted));
    }

    /// @notice THE REPLACEMENT FOR THE RETIRED MINIMUM-EDGE INVARIANT, in two halves.
    ///
    ///         First, EXACTLY: a legal ten-chip board can carry zero expected loss. That is the
    ///         whole reason the minimum-edge divisor and the break-even head count were deleted —
    ///         no positive divisor is a floor on what a seat burns when a seat may legally play a
    ///         fair game.
    ///
    ///         Second, STATISTICALLY: that same fair board is still a net burn once it is a RUN,
    ///         because a bust pays nothing and what it was holding is deleted. So the protocol's
    ///         income survives the fair legs; it just no longer comes from them.
    function test_aFairBoardCarriesNoEdgeAndIsStillANetBurn() public {
        CrapsOracle oracle = new CrapsOracle();

        // EXACT: a whole ten-chip round on true-odds legs, expected loss zero to the wei. Built
        // here as the board a picked ticket plus a scatter could legally add up to.
        Craps.Bets memory fair;
        fair.place4 = 300;
        fair.place5 = 200;
        fair.place9 = 200;
        fair.place10 = 300;
        assertEq(oracle.theoFor(fair), 0, "a true-odds board carries an edge");
        assertGt(oracle.stakeFor(fair), 0, "the fair board is empty");
        // And every other leg does carry one, so the zero above is a property of these four and
        // not of a broken theo.
        Craps.Bets memory bleeder;
        bleeder.place6 = 1000;
        assertGt(oracle.theoFor(bleeder), 0, "place 6 stopped carrying an edge");

        // EXACT, ON THE PRODUCTION PATH: the board above is not a hypothetical. A real ticket
        // naming its seven chips on true-odds legs draws three more from the dice, and those land
        // on the fair legs four times in ten each — so roughly one board in sixteen comes out
        // fair END TO END, chips the player chose and chips the table threw alike. Found here by
        // searching the word, which is the only free variable a seat has.
        bool sawFairDraw;
        for (uint256 i = 0; i < 64 && !sawFairDraw; ++i) {
            (uint256 id,) = _run(
                _board(2), 2, uint16(GOAL_FAR_MULT), uint48(50_000 + i),
                uint256(keccak256(abi.encode("fairdraw", i)))
            );
            Craps.Bets memory drawn = craps.drawnBoardOf(id);
            if (oracle.theoFor(drawn) != 0) continue;
            sawFairDraw = true;
            assertEq(oracle.stakeFor(drawn), uint256(PLAYED) * 1 ether, "a fair draw is not the whole round");
        }
        assertTrue(sawFairDraw, "no legal ticket drew a zero-edge board: the invariant may still hold");

        // STATISTICAL: a real seven-chip ticket on the fair legs, run for real. The three thrown
        // chips land wherever they land, so the RUN carries whatever edge they brought with them —
        // what is being measured here is that the table is a net burn anyway.
        Craps.Bets memory b = _board(2);
        uint8 bankMult = 4;
        uint256 bankroll = uint256(PLAYED) * bankMult * 1 ether;
        uint16 goalMult = uint16(craps.MIN_BATTLE_GOAL_MULT());

        uint256 burned;
        uint256 rawWon;
        uint256 busted;
        uint256 creditedBefore = coinflip.totalCredited();

        for (uint256 i = 0; i < 400; ++i) {
            (uint256 betId, uint64 slot) = _run(
                b, bankMult, goalMult, uint48(60_000 + i), uint256(keccak256(abi.encode("fairburn", i)))
            );
            (uint256 won, uint256 paid) = craps.previewSettlement(betId);
            craps.resolveSlot(slot, WHOLE_FIELD);
            burned += bankroll;
            rawWon += won;
            if (paid == 0) busted += won;
        }
        uint256 minted = coinflip.totalCredited() - creditedBefore;

        emit log_named_uint("fair: burned    ", burned);
        emit log_named_uint("fair: raw won   ", rawWon);
        emit log_named_uint("fair: deleted   ", busted);
        emit log_named_uint("fair: minted    ", minted);

        // The deletion is REAL and it is the whole margin: what busted runs were still holding
        // accounts for the gap between the raw result and what was minted, to within the award
        // rounding — which is EV-neutral and pinned by `test_theRoundingIsEvNeutralInAggregate`.
        assertGt(busted, 0, "no run busted holding anything: the test proves nothing");
        assertApproxEqRel(rawWon - busted, minted, 0.005e18, "the deleted remainders did not account for the gap");
        // THE SHARP ONE. Add the deleted remainders back and this board is NOT a net burn: the
        // raw result clears what was burned. So on a board built out of true-odds legs the old
        // per-leg argument does not merely weaken, it fails outright — and the deletion is the
        // entire reason the table still comes out ahead. Deterministic seeds, so this is a fact
        // about a fixed sample rather than a probabilistic claim.
        assertGt(minted + busted, burned, "the fair board was a net burn even without the deletion");
        // And with the deletion, it is.
        assertLt(minted, burned, "a fair board out-minted its burn");
        emit log_named_int("fair: raw residual", int256(burned) - int256(rawWon));
    }
}
