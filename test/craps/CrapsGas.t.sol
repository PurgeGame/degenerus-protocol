// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsViews} from "./CrapsViews.sol";
import {Test} from "forge-std/Test.sol";
import {Craps} from "../../contracts/Craps.sol";
import {LootboxCraps} from "../../contracts/LootboxCraps.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {CrapsBattle, IFlipCoin, ICoinflipStake} from "../../contracts/CrapsBattle.sol";

contract GasHarness is CrapsViews {
    /// @dev Engine tap, in exactly the flat-slip configuration a settlement runs (lean books,
    ///      dice log on). `MAX_BANKROLL_MULT` bounds what placement accepts, but the engine's own
    ///      worst case — the roll budget — is what the gas guarantee rests on, so it is measured
    ///      here with a bankroll no placement could carry.
    function engineRun(Craps.Bets calldata b, uint48 index, uint256 bankroll)
        external
        view
        returns (Craps.SlipResult memory)
    {
        return _settleSlip(b, _seedFor(index), bankroll, 0, MAX_SLIP_HANDS, SLIP_ROLL_BUDGET, address(0), 0);
    }

    /// @dev The same worst case UNDER A SCHEDULE, at the dearest terms a scheduled window can
    ///      hand it: the blank ticket's 15-in-a-hundred draw at the 50x target's +40%. A boosted
    ///      shooter costs one extra keccak and one multiply-divide, so the guarantee has to be
    ///      measured with the schedule on — an unboosted ceiling proves nothing about the common
    ///      case.
    function engineRunBoosted(Craps.Bets calldata b, uint48 index, uint256 bankroll)
        external
        view
        returns (Craps.SlipResult memory)
    {
        return _settleSlip(
            b,
            _seedFor(index),
            bankroll,
            0,
            MAX_SLIP_HANDS,
            SLIP_ROLL_BUDGET,
            address(0),
            _shooterBoostTerms(true, 50)
        );
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

    uint24 internal constant U = 120;

    uint256 internal constant TABLES = 24;
    /// @dev Covers the escalator's worst case to the cap: mandatory units over 256 hands sum to
    ///      6,946,710 even if every round loses everything.
    uint256 internal constant CAP_ROUNDS = 7_100_000;

    address internal player = makeAddr("player");

    function setUp() public {
        _installPins();
        craps = new GasHarness();
    }

    /// @dev A full board: every leg live, so this is the worst-case per-roll branch load. Only
    ///      the ENGINE sees this — an entry places seven chips, so it can light at most seven
    ///      legs itself, and nine live legs are reachable only through a board the dice place.
    function _fullBoard() internal pure returns (Craps.Bets memory b) {
        b.passLine = U * 2;
        b.place4 = U;
        b.place5 = U;
        b.place6 = U;
        b.place8 = U;
        b.place9 = U;
        b.place10 = U;
        b.hard4 = U;
        b.hard8 = U;
    }

    /// @dev The heaviest board an ENTRY can post: seven chips over seven legs, one each.
    /// @dev Chip COUNTS: seven of the round's ten, spread over as many legs as they can light —
    ///      the heaviest branch load an entry can post.
    function _placedBoard() internal pure returns (Craps.Bets memory b) {
        b.passLine = 1;
        b.place4 = 1;
        b.place5 = 1;
        b.place6 = 1;
        b.place8 = 1;
        b.place9 = 1;
        b.hard8 = 1;
    }

    /// @dev The round these fixtures play, in whole FLIP: ten chips of `U`.
    uint32 internal constant PLAYED = uint32(U) * 10;

    /// @dev Only the pass line, at the table minimum: the cheapest board, for the spread.
    function _lineOnly() internal pure returns (Craps.Bets memory b) {
        b.passLine = 700;
    }

    function _placeOnly() internal pure returns (Craps.Bets memory b) {
        b.place6 = 700;
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

        // AND WITH A SCHEDULE ON, which is what every protocol window runs. The draw fires on
        // about one shooter in seven here, so this is the cost the guarantee actually has to
        // cover — the unboosted figure above is the floor under it, not the ceiling.
        g = gasleft();
        Craps.SlipResult memory boosted = craps.engineRunBoosted(b, 70_000, bankroll);
        uint256 usedBoosted = g - gasleft();

        emit log_named_uint("engine worst-case run gas, scheduled", usedBoosted);
        emit log_named_uint("  the schedule's own cost", usedBoosted - used);
        assertEq(boosted.handsPlayed, craps.MAX_SLIP_HANDS(), "the scheduled benchmark stopped early");
        assertLt(usedBoosted, 2_250_000, "the scheduled worst case regressed past its gas budget");
    }

    /// @dev And the real surface: a max-legal slip (ten rounds of the board) placed and settled
    ///      end to end, money plumbing included.
    /// @dev A FIELD OF ONE, which is what makes this the worst case: the whole per-slot cost —
    ///      the window read, the table's word, the cursor's first write and the batched credit —
    ///      lands on the single seat instead of being spread across a field. Roughly 156k of it
    ///      is the settlement itself and the rest is that fixed plumbing, so the budget sits well
    ///      above the standalone-slip lane this replaced. What the Nth seat costs once the slot
    ///      is warm is pinned separately by `test_batchSettleMarginalCost`.
    function test_maxLegalSlipSettles() public {
        uint8 bankMult = uint8(craps.MAX_BANKROLL_MULT());
        uint64 slot = _openBattle(craps, PLAYED, bankMult, uint16(GOAL_FAR_MULT), 0);
        vm.prank(player);
        craps.enterBattle(slot, _placedBoard(), 1);
        _closeOn(craps, slot, 80_000, uint256(keccak256("maxslip")));

        uint256 g = gasleft();
        craps.resolveSlot(slot, WHOLE_FIELD);
        uint256 used = g - gasleft();

        emit log_named_uint("max-legal slip settle gas", used);
        assertLt(used, 300_000, "a max-legal slip regressed past its gas budget");
    }

    /// @dev Mass settlement. Every bet in a batch at ONE table re-reads the same VRF word through
    ///      its own external call into the game, so this measures what the Nth bet actually costs
    ///      once that account and slot are warm — the figure any grouped-resolver optimisation
    ///      would be competing against.
    function test_batchSettleMarginalCost() public {
        uint8 bankMult = uint8(craps.MAX_BANKROLL_MULT());
        uint256 n = 20;

        // One field of twenty, and a field of one on identical terms, so the difference is purely
        // what the Nth entrant costs once the slot's word, terms and scoreboard are warm.
        uint64 many = _openBattle(craps, PLAYED, bankMult, uint16(GOAL_FAR_MULT), 0);
        vm.startPrank(player);
        for (uint256 i = 0; i < n; ++i) {
            craps.enterBattle(many, _placedBoard(), 1);
        }
        vm.stopPrank();
        _closeOn(craps, many, 90_000, uint256(keccak256("batch")));

        uint64 lone = _openBattle(craps, PLAYED, bankMult, uint16(GOAL_FAR_MULT), 1);
        vm.prank(player);
        craps.enterBattle(lone, _placedBoard(), 1);
        _closeOn(craps, lone, 90_001, uint256(keccak256("batch")));

        uint256 g = gasleft();
        craps.resolveSlot(lone, WHOLE_FIELD);
        uint256 single = g - gasleft();

        g = gasleft();
        craps.resolveSlot(many, WHOLE_FIELD);
        uint256 batch = g - gasleft();

        emit log_named_uint("one bet settled alone     ", single);
        emit log_named_uint("field of 20, total        ", batch);
        emit log_named_uint("field of 20, per bet      ", batch / n);
        emit log_named_uint("saved per bet by the field", single - batch / n);
    }

    function _ids(uint64 a) internal pure returns (uint64[] memory out) {
        out = new uint64[](1);
        out[0] = a;
    }

    /// @dev The battle's own overhead, measured where it lands: placement's group bump (the first
    ///      entrant pays the slot, the rest a warm RMW), and the one-transaction lane that
    ///      settles an index and pays its winners in the same call.
    function test_battleFlowGas() public {
        uint8 bankMult = uint8(craps.MAX_BANKROLL_MULT());
        uint256 bank = uint256(PLAYED) * bankMult * 1 ether;
        // The bounty may be anything up to the bankroll; take a small slice of it.
        uint24 su = uint24(bank / (5 * craps.BATTLE_STAKE_UNIT()) + 1);

        uint256 g = gasleft();
        uint64 slot = _openBattle(craps, PLAYED, bankMult, uint16(GOAL_FAR_MULT), su);
        uint256 create = g - gasleft();

        vm.startPrank(player);
        g = gasleft();
        craps.enterBattle(slot, _placedBoard(), 1);
        uint256 firstSeat = g - gasleft();

        g = gasleft();
        craps.enterBattle(slot, _placedBoard(), 1);
        uint256 nextSeat = g - gasleft();
        vm.stopPrank();

        g = gasleft();
        _closeOn(craps, slot, 85_000, uint256(keccak256("battlegas")));
        uint256 close = g - gasleft();

        g = gasleft();
        craps.resolveSlot(slot, WHOLE_FIELD);
        uint256 settle = g - gasleft();

        emit log_named_uint("createBattle              ", create);
        emit log_named_uint("enterBattle, first seat   ", firstSeat);
        emit log_named_uint("enterBattle, later seat   ", nextSeat);
        emit log_named_uint("closeBattle               ", close);
        emit log_named_uint("resolveSlot, field of 2   ", settle);   // pays, too
        assertLt(settle, 1_200_000, "the one-transaction field settle regressed");
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
