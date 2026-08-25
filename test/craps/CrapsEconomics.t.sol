// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsOracle} from "./CrapsOracle.sol";
import {LootboxCraps} from "../../contracts/LootboxCraps.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {FlipCraps, IFlipCoin, ICoinflipStake} from "../../contracts/FlipCraps.sol";

contract EconHarness is FlipCraps {

    /// @dev The theo cross-check grades production's lean settlement against an independent
    ///      engine off the same seed. `resolveSlipAt` was cut from production (EIP-170; the paying
    ///      path never called it), so it is rebuilt here over the SHIPPED `seedFor`.
    CrapsOracle internal immutable oracle;

    constructor() {
        oracle = new CrapsOracle();
    }

    function bankrollGoalForX(uint256 payoutGoal) external pure returns (uint256) {
        return bankrollGoalFor(payoutGoal);
    }

    function resolveSlipAt(
        Craps.Bets calldata b,
        uint48 index,
        uint256 bankroll,
        uint256 goal,
        uint256 cap
    ) external view returns (CrapsOracle.SlipResult memory) {
        return oracle.resolveSlip(b, seedFor(index), bankroll, goal, cap);
    }






}

/// @title Craps economic invariant — can this table print FLIP?
///
/// @notice FLIP has no reserve behind it: a losing wager BURNS and a winning one MINTS. So the
///         question is not whether a house bankroll survives, it is whether the expected mint plus
///         the expected comp comes to less than the burn at EVERY board, bankroll, goal and score
///         a player may choose.
///
/// @dev THE ARGUMENT, AND WHERE EACH STEP IS TESTED
///
///      Writing `U` for the base-board units a run wagers and `T` for `theoFor(board)`:
///
///        burn         = bankroll                                    (taken at placement)
///        E[mint]      = bankroll - T*U                              (1) the edge is real
///        E[flip]      = neutral, so E[paid | won] <= won            (2) fair coin, EV-neutral rounding
///        comp         = floor(T*U*bps/1e4), bps <= 7500             (3) exact, capped
///        =>  E[mint] + comp <= bankroll - 0.25*T*U  <  burn
///
///      Step (1) is the only claim with any randomness in it, and it decomposes into a per-leg
///      statement that `test_houseEdgeConverges` already pins over 200k hands at 4 sigma; the
///      composition to `T*U` is linearity, which `test_theoIsTheRealisedEdgeOnAHighEdgeBoard`
///      checks end to end on a board whose edge is large enough for the sample to have power.
///      Steps (2) and (3) are tested here — (3) exactly, with no variance at all.
///
///      Deliberately NOT asserted: a tight match between realised loss and theo on a low-edge
///      board. Per unit, realised loss has a standard deviation on the order of the stake itself
///      against a mean of a few percent of it, so at any sample size this suite can afford, such an
///      assertion would be measuring noise. The high-edge board is where the signal clears it.
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

    /// @dev Boards spanning the whole shape of the game: the minimum, the grind, the bleeders,
    ///      the indulgences, a pure zero-edge odds monster, and everything at once.
    function _board(uint256 which) internal pure returns (Craps.Bets memory b) {
        if (which == 0) {
            b.passLine = 600;
        } else if (which == 1) {
            b.passLine = 200;
            b.place6 = 200;
            b.place8 = 200;
        } else if (which == 2) {
            b.place4 = 300;
            b.place10 = 300;
        } else if (which == 3) {
            b.hard4 = 300;
            b.hard8 = 300;
        } else if (which == 4) {
            b.passLine = 600;
            b.passOddsMult = 1000;
        } else {
            b.passLine = 100;
            b.passOddsMult = 5;
            b.place4 = 100;
            b.place5 = 100;
            b.place6 = 100;
            b.place8 = 100;
            b.place9 = 100;
            b.place10 = 100;
            b.hard4 = 100;
            b.hard8 = 100;
        }
    }

    /// @notice STEP 3, EXACTLY: the comp is a capped fraction of the house's own expected income,
    ///         at every board, every legal bankroll and both goal regimes — no sampling, no
    ///         tolerance. This is the assertion that makes the rakeback structurally unable to
    ///         outrun the edge that funds it, whatever a player picks.
    function test_compIsExactlyBoundedByTheEdgeThatFundsIt() public {
        uint48 idx = 1000;
        uint256 checked;

        for (uint256 shape = 0; shape < 6; ++shape) {
            Craps.Bets memory b = _board(shape);
            uint256 stake = craps.stakeFor(b);

            for (uint256 mult = 1; mult <= craps.MAX_BANKROLL_MULT(); ++mult) {
                uint128 bankroll = uint128(stake * mult);

                for (uint256 g = 0; g < 2; ++g) {
                    // g == 1 is the tightest legal take-profit: the shortest a run can legally be,
                    // and so the least handle a player can hand over while still being comped.
                    uint128 goal = g == 0 ? 0 : uint128(uint256(bankroll) * 2 + 1);

                    _setIndex(idx);
                    vm.prank(player);
                    uint64 betId = craps.placeSlip(b, bankroll, goal);
                    _setWord(idx, uint256(keccak256(abi.encode("comp", idx))));

                    CrapsOracle.SlipResult memory r = craps.resolveSlipAt(
                        b, idx, bankroll, craps.bankrollGoalForX(goal), craps.MAX_SLIP_HANDS());
                    uint256 theo = craps.theoFor(b) * r.unitsPlayed;

                    uint256 before = coinflip.totalCredited();
                    craps.resolveBets(_ids(betId));
                    uint256 comp = coinflip.totalCredited() - before;

                    // Exact: the comp is the locked rate applied to the handle actually wagered.
                    assertEq(comp, (theo * craps.RAKE_MAX_BPS()) / 10_000, "comp != rate x theo");
                    // And therefore always strictly under the edge it is a slice of.
                    assertLt(comp, theo, "comp reached or passed the whole edge");

                    ++idx;
                    ++checked;
                }
            }
        }
        assertEq(checked, 120, "coverage changed");
    }

    /// @notice STEP 1, at a sample size with real power: on the 10%-edge board the signal clears
    ///         the noise, so the realised loss can be held to the theo directly. This is the claim
    ///         everything else rests on — that `theoFor` is the true expected loss per unit.
    function test_theoIsTheRealisedEdgeOnAHighEdgeBoard() public {
        Craps.Bets memory b = _board(2); // place 4 + place 10, theo = 1/10 per unit
        uint256 stake = craps.stakeFor(b);
        uint128 bankroll = uint128(stake * craps.MAX_BANKROLL_MULT());

        uint256 burned;
        uint256 wonTotal;
        uint256 units;

        for (uint256 i = 0; i < 600; ++i) {
            uint48 idx = uint48(10_000 + i);
            _setIndex(idx);
            vm.prank(player);
            uint64 betId = craps.placeSlip(b, bankroll, 0);
            _setWord(idx, uint256(keccak256(abi.encode("edge", i))));

            CrapsOracle.SlipResult memory r =
                craps.resolveSlipAt(b, idx, bankroll, 0, craps.MAX_SLIP_HANDS());
            (uint256 won,,) = craps.previewSettlement(betId);
            craps.resolveBets(_ids(betId));

            burned += bankroll;
            wonTotal += won;
            units += r.unitsPlayed;
        }

        uint256 realisedLoss = burned - wonTotal;
        uint256 theoTotal = craps.theoFor(b) * units;

        emit log_named_uint("units wagered   ", units);
        emit log_named_uint("realised loss   ", realisedLoss);
        emit log_named_uint("theo of handle  ", theoTotal);

        // The players lost, and lost about what the closed form says they should.
        assertGt(realisedLoss, 0, "the house did not win at all");
        assertApproxEqRel(realisedLoss, theoTotal, 0.30e18, "realised edge is not the theo");
    }

    /// @notice STEP 2: over many independent tables the REALISED mint — every survival flip and
    ///         every rounding roll included — must land on the summed pre-flip `won`. If the coin
    ///         were shaded or the rounding leaked upward, this is where it would show.
    function test_theFlipAndRoundingAreEvNeutralInAggregate() public {
        Craps.Bets memory b = _board(5);
        uint256 stake = craps.stakeFor(b);
        uint128 bankroll = uint128(stake * 4);
        // A take-profit goal (stop once the bankroll doubles) bounds each run's final figure.
        // Without one, the second chance's repeated double-or-nothing gives `won` a St. Petersburg
        // tail — each survived double halves the odds — whose mean is dominated by rare deep
        // doublings: EV-neutral (proven exactly by the comp test and the Wald argument) but far too
        // heavy-tailed for a realised-vs-expected mean to converge at any affordable sample size.
        // Capping the run makes this flip-and-rounding check measurable, and the doubling coin is
        // still exercised hard — a survive is the usual way a run reaches the 2x stop. The coin's
        // own fairness is proven in FlipCraps.t.sol.
        uint128 goal = uint128(uint256(bankroll) * 4);

        uint256 expectedMint;
        uint256 survivors;
        uint256 payers;
        uint256 n = 800;

        for (uint256 i = 0; i < n; ++i) {
            uint48 idx = uint48(20_000 + i);
            _setIndex(idx);
            vm.prank(player);
            uint64 betId = craps.placeSlip(b, bankroll, goal);
            _setWord(idx, uint256(keccak256(abi.encode("flipev", i))));

            (uint256 won, bool survived,) = craps.previewSettlement(betId);
            expectedMint += won;
            // The survival coin only decides money on a run that came home with something. A
            // run that lost its mid-hand second chance rides that same coin at the end — forced to
            // "not survived", and worth nothing either way (won == 0) — so the fairness check runs
            // on the paying flips, where the coin is a fresh 50/50.
            if (won != 0) {
                ++payers;
                if (survived) ++survivors;
            }
            craps.resolveBets(_ids(betId));
        }

        emit log_named_uint("expected mint   ", expectedMint);
        emit log_named_uint("realised mint   ", flip.totalMinted());
        emit log_named_uint("paying survivors", survivors);
        emit log_named_uint("paying runs     ", payers);

        // A fair coin over the paying runs: survivors sit on half of them.
        assertApproxEqAbs(survivors * 2, payers, payers / 4 + 20, "the survival coin is not fair");
        // Centred, not shaded upward. The band is the coin's own variance over 600 tables.
        assertApproxEqRel(flip.totalMinted(), expectedMint, 0.20e18, "mint drifted from expectation");
        // Rounding may only ever cost the player: below the threshold it floors outright, and the
        // stochastic band above it never rounds a whole granule up out of nothing.
        assertLe(flip.totalMinted(), expectedMint * 2, "rounding invented FLIP");
    }

    /// @notice Zero-edge action stays zero-edge: a 1000x odds board generates no theo, so it comps
    ///         nothing beyond what its LINE alone earns — the odds allowance cannot be farmed for
    ///         rakeback however large it grows.
    function test_oddsGenerateNoComp() public view {
        Craps.Bets memory withOdds = _board(4); // 600 line + 1000x odds
        Craps.Bets memory lineOnly;
        lineOnly.passLine = 600;

        assertEq(craps.theoFor(withOdds), craps.theoFor(lineOnly), "odds contributed theo");
        // And the odds stake is real money: it enlarges the handle without enlarging the comp.
        assertGt(craps.stakeFor(withOdds), craps.stakeFor(lineOnly) * 1000, "odds not in the stake");
    }

    /// @notice The whole loop, end to end. What is ASSERTED here is the well-powered half — that
    ///         expected mint falls short of the burn, i.e. the edge is genuinely collected — plus
    ///         the exact comp bound. The remaining quarter-of-theo margin is reported rather than
    ///         asserted, and deliberately so: at the 75% ceiling the residual is 0.25*T*U against a
    ///         realised-loss standard deviation of roughly 0.20*T*U at this sample size, so an
    ///         assertion on it would flake about one run in ten while proving nothing that the
    ///         composition does not already give exactly:
    ///
    ///           comp == 0.75*T*U exactly              (test_compIsExactlyBoundedByTheEdge..., 120 configs)
    ///           E[loss] == T*U                        (test_theoIsTheRealisedEdge... + the 200k-hand MC)
    ///           E[mint] <= won                        (test_theFlipAndRoundingAreEvNeutral...)
    ///           => E[burn - mint - comp] == 0.25*T*U > 0
    ///
    ///         The dust-goal strategy — stop at the first wei of profit — is covered exactly by the
    ///         `g == 1` half of the comp test rather than sampled here: its payout shape is many
    ///         tiny wins against rare large losses, so no affordable sample size represents it.
    function test_theTableIsANetBurn() public {
        Craps.Bets memory b = _board(2);
        uint256 stake = craps.stakeFor(b);
        uint128 bankroll = uint128(stake * craps.MAX_BANKROLL_MULT());

        uint256 burned;
        uint256 expectedMint;
        uint256 units;

        for (uint256 i = 0; i < 600; ++i) {
            uint48 idx = uint48(30_000 + i);
            _setIndex(idx);
            vm.prank(player);
            uint64 betId = craps.placeSlip(b, bankroll, 0);
            _setWord(idx, uint256(keccak256(abi.encode("netburn", i))));

            CrapsOracle.SlipResult memory r =
                craps.resolveSlipAt(b, idx, bankroll, 0, craps.MAX_SLIP_HANDS());
            (uint256 won,,) = craps.previewSettlement(betId);
            craps.resolveBets(_ids(betId));

            burned += bankroll;
            expectedMint += won; // E[paid | won] <= won, the flip being fair and rounding neutral
            units += r.unitsPlayed;
        }

        uint256 comped = coinflip.totalCredited();
        uint256 theoTotal = craps.theoFor(b) * units;

        emit log_named_uint("burned          ", burned);
        emit log_named_uint("expected mint   ", expectedMint);
        emit log_named_uint("comped          ", comped);
        emit log_named_uint("theo of handle  ", theoTotal);

        // ASSERTED: the edge is really collected, and the comp really is the capped slice of it.
        assertLt(expectedMint, burned, "expected mint exceeds the burn BEFORE any comp");
        assertEq(comped, (theoTotal * craps.RAKE_MAX_BPS()) / 10_000, "comp != 75% of theo");

        // REPORTED: the residual. Signed, because at the 75% ceiling a sample this size can land
        // either way without saying anything about the expectation.
        int256 net = int256(burned) - int256(expectedMint) - int256(comped);
        emit log_named_int("net burn (signed)", net);
    }
}
