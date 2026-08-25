// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Craps} from "../../contracts/Craps.sol";
import {LootboxCraps} from "../../contracts/LootboxCraps.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {FlipCraps, IFlipCoin, ICoinflipStake} from "../../contracts/FlipCraps.sol";

contract GasHarness is FlipCraps {
    /// @dev Engine tap, in exactly the flat-slip configuration a settlement runs (lean books,
    ///      dice log on). `MAX_BANKROLL_MULT` bounds what placement accepts, but the engine's own
    ///      worst case — the roll budget — is what the gas guarantee rests on, so it is measured
    ///      here with a bankroll no placement could carry.
    function engineRun(Craps.Bets calldata b, uint48 index, uint256 bankroll)
        external
        view
        returns (Craps.SlipResult memory)
    {
        return _settleSlip(b, seedFor(index), bankroll, 0, MAX_SLIP_HANDS, SLIP_ROLL_BUDGET);
    }
}

/// @title Craps resolution gas benchmark
/// @notice Measures what one more shooter actually costs, rather than asserting a guess. The slip
///         has to settle inside one transaction, so the numbers underneath `MAX_SLIP_HANDS` and
///         `SLIP_ROLL_BUDGET` should be measured and kept honest.
///
/// @dev Method: the engine tap runs the same board at the SAME index twice — once with a bankroll
///      covering one round, once with one that survives the escalator to the shooter cap. The
///      table is shared and hand `i` is a pure function of `(seed, i)`, so the small run's hands
///      are byte-for-byte a prefix of the big run's — the gas difference is exactly the extra
///      shooters, divided by the count the engine itself reports. Hand length is geometric with a
///      long tail, so this is averaged over many independent tables.
contract CrapsGasTest is CrapsPins {
    GasHarness internal craps;

    uint24 internal constant U = 100;

    uint256 internal constant TABLES = 24;
    /// @dev Covers the escalator's worst case to the cap: mandatory units over 256 hands sum to
    ///      6,946,710 even if every round loses everything.
    uint256 internal constant CAP_ROUNDS = 7_100_000;

    address internal player = makeAddr("player");

    function setUp() public {
        _installPins();
        craps = new GasHarness();
    }


    /// @dev A full board: every leg live, so this is the worst-case per-roll branch load.
    function _fullBoard() internal pure returns (Craps.Bets memory b) {
        b.passLine = U;
        b.passOddsMult = 3;
        b.place4 = U;
        b.place5 = U;
        b.place6 = U;
        b.place8 = U;
        b.place9 = U;
        b.place10 = U;
        b.hard4 = U;
        b.hard8 = U;
    }

    /// @dev Only the pass line, at the table minimum: the cheapest board, for the spread.
    function _lineOnly() internal pure returns (Craps.Bets memory b) {
        b.passLine = 600;
    }

    function _placeOnly() internal pure returns (Craps.Bets memory b) {
        b.place6 = 600;
    }

    /// @dev The engine's worst case — a run the escalator cannot bust, stopped only by the shooter
    ///      cap or the roll budget — must stay comfortably inside a block, whatever placement's
    ///      bankroll cap keeps players themselves from reaching.
    function test_engineWorstCaseIsSettleable() public {
        Craps.Bets memory b = _fullBoard();
        _setWord(70_000, uint256(keccak256("capslip")));

        uint256 bankroll = craps.stakeFor(b) * CAP_ROUNDS;
        uint256 g = gasleft();
        Craps.SlipResult memory result = craps.engineRun(b, 70_000, bankroll);
        uint256 used = g - gasleft();

        emit log_named_uint("engine worst-case run gas", used);
        assertEq(result.handsPlayed, craps.MAX_SLIP_HANDS(), "benchmark did not reach the shooter cap");
        assertLt(used, 2_250_000, "the engine's worst case regressed past its gas budget");
    }

    /// @dev And the real surface: a max-legal slip (ten rounds of the board) placed and settled
    ///      end to end, money plumbing included.
    function test_maxLegalSlipSettles() public {
        Craps.Bets memory b = _fullBoard();
        _setIndex(80_000);

        uint128 bankroll = uint128(craps.stakeFor(b) * craps.MAX_BANKROLL_MULT());
        vm.prank(player);
        uint64 betId = craps.placeSlip(b, bankroll, 0);
        _setWord(80_000, uint256(keccak256("maxslip")));

        uint256 g = gasleft();
        craps.resolveBets(_ids(betId));
        uint256 used = g - gasleft();

        emit log_named_uint("max-legal slip settle gas", used);
        assertLt(used, 250_000, "a max-legal slip regressed past its gas budget");
    }

    /// @dev Mass settlement. Every bet in a batch at ONE table re-reads the same VRF word through
    ///      its own external call into the game, so this measures what the Nth bet actually costs
    ///      once that account and slot are warm — the figure any grouped-resolver optimisation
    ///      would be competing against.
    function test_batchSettleMarginalCost() public {
        Craps.Bets memory b = _fullBoard();
        uint256 stake = craps.stakeFor(b);
        uint48 idx = 90_000;
        _setIndex(idx);

        uint256 n = 20;
        uint64[] memory many = new uint64[](n);
        vm.startPrank(player);
        for (uint256 i = 0; i < n; ++i) {
            many[i] = craps.placeSlip(b, uint128(stake * craps.MAX_BANKROLL_MULT()), 0);
        }
        uint64 lone = craps.placeSlip(b, uint128(stake * craps.MAX_BANKROLL_MULT()), 0);
        vm.stopPrank();
        _setWord(idx, uint256(keccak256("batch")));

        uint256 g = gasleft();
        craps.resolveBets(_ids(lone));
        uint256 single = g - gasleft();

        g = gasleft();
        craps.resolveBets(many);
        uint256 batch = g - gasleft();

        emit log_named_uint("one bet settled alone     ", single);
        emit log_named_uint("batch of 20, total        ", batch);
        emit log_named_uint("batch of 20, per bet      ", batch / n);
        // Identical bets at one table, so the only difference is warm state and loop overhead.
        emit log_named_uint("saved per bet by batching ", single - batch / n);
    }

    function _ids(uint64 a) internal pure returns (uint64[] memory out) {
        out = new uint64[](1);
        out[0] = a;
    }

    function test_marginalShooterCost() public {
        _measure(_fullBoard(), "full board (all 10 legs)", 50_000);
        _measure(_lineOnly(), "pass line only", 60_000);
        _measure(_placeOnly(), "place six only", 65_000);
    }

    function _measure(Craps.Bets memory b, string memory label, uint48 base) internal {
        uint256 gasSmall;
        uint256 gasBig;
        uint256 handsSmall;
        uint256 handsBig;
        uint256 rollsSmall;
        uint256 rollsBig;
        uint256 stake = craps.stakeFor(b);

        for (uint256 i = 0; i < TABLES; ++i) {
            uint48 idx = uint48(base + i);
            _setWord(idx, uint256(keccak256(abi.encode("gas", base, i))));

            uint256 g = gasleft();
            Craps.SlipResult memory small = craps.engineRun(b, idx, stake);
            gasSmall += g - gasleft();

            g = gasleft();
            Craps.SlipResult memory big = craps.engineRun(b, idx, stake * CAP_ROUNDS);
            gasBig += g - gasleft();

            handsSmall += small.handsPlayed;
            handsBig += big.handsPlayed;
            rollsSmall += small.totalRolls;
            rollsBig += big.totalRolls;
        }

        uint256 marginalHands = handsBig - handsSmall;
        uint256 marginalGas = gasBig - gasSmall;
        uint256 marginalRolls = rollsBig - rollsSmall;

        emit log_named_string("board", label);
        emit log_named_uint("  gas per marginal shooter ", marginalGas / marginalHands);
        emit log_named_uint("  mean rolls per shooter   ", (marginalRolls * 100) / marginalHands);
        emit log_named_uint("  gas per roll             ", marginalGas / marginalRolls);

        // The cap exists so a slip always settles inside one transaction. If a change to the
        // resolver ever pushes a cap-length run near a block's worth of gas, the cap is no longer
        // doing its job and this fails rather than quietly shipping an unsettleable slip.
        assertLt(
            (marginalGas / marginalHands) * craps.MAX_SLIP_HANDS(),
            2_250_000,
            "a cap-length run regressed past its gas budget"
        );
    }

}
