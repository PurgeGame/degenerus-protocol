// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsViews} from "./CrapsViews.sol";
import {Test} from "forge-std/Test.sol";
import {Craps} from "../../contracts/Craps.sol";
import {LootboxCraps} from "../../contracts/LootboxCraps.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {CrapsBattle, IFlipCoin, ICoinflipStake} from "../../contracts/CrapsBattle.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

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
        return _settleSlip(b, _seedFor(index), bankroll, 0, MAX_SLIP_HANDS, SLIP_ROLL_BUDGET, 0, 0);
    }

    /// @dev The same worst case with the blank ticket's 30% suffix-profit bonus after
    ///      12 rolls. Measure the threshold loop and final bonus arithmetic as well.
    function engineRunBoosted(Craps.Bets calldata b, uint48 index, uint256 bankroll)
        external
        view
        returns (Craps.SlipResult memory)
    {
        return _settleSlip(
            b, _seedFor(index), bankroll, 0, MAX_SLIP_HANDS, SLIP_ROLL_BUDGET, 0, _shooterBoostTerms(0)
        );
    }

    /// @dev The boosted worst case under a caller-chosen between-shooters roll budget.
    function engineRunBudget(Craps.Bets calldata b, uint48 index, uint256 bankroll, uint256 budget)
        external
        view
        returns (Craps.SlipResult memory)
    {
        return _settleSlip(b, _seedFor(index), bankroll, 0, MAX_SLIP_HANDS, budget, 0, _shooterBoostTerms(0));
    }

    /// @dev The scheduled engine with the high-water lifecycle actually ON — a live goal, so the
    ///      run latches and plays past it under the protected reserve.
    function engineRunScheduled(Craps.Bets calldata b, uint48 index, uint256 bankroll, uint256 goal, address player)
        external
        view
        returns (Craps.SlipResult memory)
    {
        return _settleSlip(
            b, _seedFor(index), bankroll, goal, MAX_SLIP_HANDS, SLIP_ROLL_BUDGET, uint256(uint160(player)), _shooterBoostTerms(0)
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
    /// @dev The bankroll, in base-board rounds, that funds a run all the way to its 512-shooter
    ///      cap. The escalator doubles every three shooters to shooter 30, then every shooter,
    ///      and wagers `uint32.max` from shooter 52, so the whole book is about 461 * 2^32, just
    ///      under 1.98e12 rounds — three orders of magnitude past anything the schedule can hand a
    ///      player, which is exactly what makes it the engine's worst case rather than a
    ///      reachable one.
    uint256 internal constant CAP_ROUNDS_TO_SHOOTER_CAP = 2_000_000_000_000;

    address internal player = makeAddr("player");

    function setUp() public {
        _installPins();
        craps = new GasHarness();
        // Genesis is a Craps warm-up day; every fixture plays from genesis + 1.
        vm.warp(block.timestamp + 1 days);
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
        _setWord(0, uint256(keccak256("capslip")));

        uint256 bankroll = craps.stakeFor(b) * CAP_ROUNDS_TO_SHOOTER_CAP;
        uint256 g = gasleft();
        Craps.SlipResult memory result = craps.engineRun(b, 0, bankroll);
        uint256 used = g - gasleft();

        emit log_named_uint("engine worst-case run gas", used);
        assertGe(result.totalRolls, craps.SLIP_ROLL_BUDGET(), "benchmark did not reach the roll budget");
        assertLe(result.totalRolls, craps.SLIP_ROLL_CEILING(), "benchmark passed the roll ceiling");
        assertLt(used, 3_000_000, "the engine's worst case regressed past its gas budget");

        // AND THE SAME RUN WITH A SCHEDULE ON, which is what every protocol window runs: a draw
        // on about one shooter in seven, each costing an extra keccak and a multiply-divide. The
        // unboosted figure above is the floor under it, not the ceiling.
        g = gasleft();
        Craps.SlipResult memory boosted = craps.engineRunBoosted(b, 0, bankroll);
        uint256 usedBoosted = g - gasleft();

        emit log_named_uint("engine worst-case run gas, scheduled", usedBoosted);
        emit log_named_uint("  shooters                          ", boosted.handsPlayed);
        emit log_named_uint("  rolls                             ", boosted.totalRolls);
        assertGe(boosted.totalRolls, craps.SLIP_ROLL_BUDGET(), "the scheduled benchmark stopped early");
        assertLt(usedBoosted, 3_000_000, "the scheduled worst case regressed past its gas budget");

        // THE ABSOLUTE ROLL CEILING is not the budget: the budget is judged BETWEEN shooters, so
        // the last shooter it admits may still run a full hand of its own.
        assertLe(boosted.totalRolls, craps.SLIP_ROLL_CEILING(), "a run passed the absolute roll ceiling");
        assertEq(
            craps.SLIP_ROLL_CEILING(),
            craps.SLIP_ROLL_BUDGET() - 1 + craps.MAX_ROLLS(),
            "the stated ceiling is not budget - 1 + one whole hand"
        );
        assertEq(craps.SLIP_ROLL_CEILING(), 1111, "the roll ceiling moved");
    }

    /// @dev THE SEAT BOUND'S ENGINE TERM, from above. The real ceiling shape is a 599-roll budget
    ///      followed by one whole 512-roll hand (1,111 rolls); a 512-roll hand is unreachable by
    ///      search, so the run is instead held to a 1,111-roll between-shooters budget: at least
    ///      1,111 rolls over more shooters than the ceiling shape, so at least its cost (per-roll
    ///      work is outcome-independent; every extra shooter only adds). Cold engine frame.
    function test_engineRollCeilingUpperBound() public {
        Craps.Bets memory b = _fullBoard();
        uint256 bankroll = craps.stakeFor(b) * CAP_ROUNDS_TO_SHOOTER_CAP;
        uint256 worst;
        uint256 worstRolls;
        for (uint256 i; i < 8; ++i) {
            _setWord(0, uint256(keccak256(abi.encode("ceiling", i))));
            vm.cool(address(craps));
            uint256 g = gasleft();
            Craps.SlipResult memory r = craps.engineRunBudget(b, 0, bankroll, craps.SLIP_ROLL_CEILING());
            uint256 used = g - gasleft();
            assertGe(r.totalRolls, craps.SLIP_ROLL_CEILING(), "the run reached the ceiling roll count");
            // Normalize the overshoot past 1,111 rolls back to the ceiling.
            used = used * craps.SLIP_ROLL_CEILING() / r.totalRolls;
            if (used > worst) { worst = used; worstRolls = r.totalRolls; }
        }
        emit log_named_uint("SEAT engine 1,111-roll upper bound (cold, normalized)", worst);
        emit log_named_uint("  rolls of that run", worstRolls);
        // The rest of a seat is bounded by the cold one-seat field rail (window, word, cursor,
        // finalization and credit flush), asserted below 240k in test_batchSettleMarginalCost.
        emit log_named_uint("SEAT cold worst estimate (engine ceiling + one-seat field rail)", worst + 240_000);
        assertLe((worst + 240_000) * 12 / 10, GasBounds.CRAPS_SEAT_GAS_MAX, "seat bound keeps a 20% margin");
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
        _closeOn(craps, slot, 0, uint256(keccak256("maxslip")));

        uint256 g = gasleft();
        craps.settleSlot(slot, WHOLE_FIELD);
        uint256 used = g - gasleft();

        emit log_named_uint("max-legal slip settle gas", used);
        // Tagged scheduled readers add dispatch/check overhead even on this custom
        // path. Allow 2k above the prior sample bound; the keeper's 1.65M seat
        // envelope and separate 10M chunk assertions stay unchanged.
        assertLt(used, 212_000, "a max-legal slip regressed past its gas budget");
    }

    /// @dev Mass settlement. Every bet in a batch at ONE table re-reads the same VRF word through
    ///      its own external call into the game, so this measures what the Nth bet actually costs
    ///      once that account and slot are warm — the figure any grouped-resolver optimisation
    ///      would be competing against.
    function test_batchSettleMarginalCost() public {
        // Revert all setup between branches: both fields now have the same custom
        // slot (part of the dice seed), word, owner, chips, bankroll and zero bounty.
        uint256 snapshot = vm.snapshotState();
        (uint256 single, uint64 lone) = _measureComparableField(1);
        assertTrue(vm.revertToState(snapshot), "restore identical field pre-state");
        (uint256 batch, uint64 many) = _measureComparableField(20);
        assertEq(lone, many, "custom slot is part of the committed engine seed");

        emit log_named_uint("one bet settled alone", single);
        emit log_named_uint("field of 20, total", batch);
        emit log_named_uint("field of 20, per bet", batch / 20);
        uint256 marginal = (batch - single) / 19;
        emit log_named_uint("gas per additional settled seat", marginal);
        emit log_named_uint("saved per bet by the field", single - batch / 20);
        assertLt(single, 240_000, "a cold one-seat settlement regressed");
        assertLt(batch, 2_050_000, "a twenty-seat settlement regressed");
        assertLt(marginal, 105_000, "the warm marginal seat regressed");
    }

    function _measureComparableField(uint256 n) private returns (uint256 used, uint64 slot) {
        slot = _openBattle(craps, PLAYED, uint8(craps.MAX_BANKROLL_MULT()), uint16(GOAL_FAR_MULT), 0);
        vm.startPrank(player);
        uint256 first;
        uint256 last;
        for (uint256 i; i < n; ++i) {
            last = craps.enterBattle(slot, _placedBoard(), 1);
            if (i == 0) first = last;
        }
        vm.stopPrank();
        _closeOn(craps, slot, 0, uint256(keccak256("batch")));
        _coolSettlement();
        uint256 intrinsic = _intrinsic(abi.encodeWithSelector(craps.settleSlot.selector, slot, WHOLE_FIELD));
        uint256 g = gasleft();
        craps.settleSlot{gas: 10_000_000 - intrinsic}(slot, WHOLE_FIELD);
        used = g - gasleft();
        assertEq(craps.bonusCursorOf(slot), n, "every seat must settle");
        assertTrue(craps.betOf(first).settled && craps.betOf(last).settled, "both ends of field settled");
        assertLt(used + intrinsic, 10_000_000, "cold settlement transaction cap");
    }

    function _coolSettlement() private {
        vm.cool(address(craps));
        vm.cool(address(game));
        vm.cool(address(flip));
        vm.cool(address(coinflip));
        vm.cool(ContractAddresses.CRAPS_ENGINE);
    }

    function _intrinsic(bytes memory data) private pure returns (uint256 gasCost) {
        gasCost = 21_000;
        for (uint256 i; i < data.length; ++i) {
            gasCost += data[i] == 0 ? 4 : 16;
        }
    }

    function _ids(uint64 a) internal pure returns (uint64[] memory out) {
        out = new uint64[](1);
        out[0] = a;
    }

    /// @dev The battle's own overhead, measured where it lands: placement's group bump (the first
    ///      entrant pays the slot, the rest a warm RMW), and the one-transaction lane that
    ///      settles an index and pays its winners in the same call.
    function test_battleFlowGas() public {
        _battleFlowGas(true);
    }

    function test_battleFlowGas_WarmSingleTransaction() public {
        assertLt(this.measureWarmBattleFlow(), 280_000, "warm field settle regressed");
    }

    function measureWarmBattleFlow() external returns (uint256) {
        require(msg.sender == address(this), "test self-call only");
        // One outer transaction, even with --isolate: all setup and settlement
        // below are nested calls and retain the original benchmark's warm state.
        return _battleFlowGas(false);
    }

    function _battleFlowGas(bool cold) private returns (uint256 settle) {
        uint8 bankMult = uint8(craps.MAX_BANKROLL_MULT());
        uint256 bank = uint256(PLAYED) * bankMult * 1;
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
        _closeOn(craps, slot, 0, uint256(keccak256("battlegas")));
        uint256 close = g - gasleft();

        if (cold) {
            _coolSettlement();
            vm.record();
        }
        uint256 intrinsic = _intrinsic(abi.encodeWithSelector(craps.settleSlot.selector, slot, WHOLE_FIELD));
        g = gasleft();
        craps.settleSlot{gas: 10_000_000 - intrinsic}(slot, WHOLE_FIELD);
        settle = g - gasleft();
        if (cold) {
            assertLt(settle, 280_000 + _fieldColdAllowance(), "cold field exceeds warm budget plus storage allowance");
        }
        assertEq(craps.bonusCursorOf(slot), 2, "both bounty-bearing seats settled");
        assertLt(settle + intrinsic, 10_000_000, "field transaction exceeds review cap");

        emit log_named_uint("createBattle              ", create);
        emit log_named_uint("enterBattle, first seat   ", firstSeat);
        emit log_named_uint("enterBattle, later seat   ", nextSeat);
        emit log_named_uint("closeBattle               ", close);
        emit log_named_uint("settle, field of 2        ", settle); // pays, too
    }

    /// @dev The measured 280k warm ceiling remains a separate regression. This
    /// conservative allowance uses the bounded storage footprint and EVM cold-read
    /// / fresh-rewrite costs, not the observed cold gas number.
    function _fieldColdAllowance() private returns (uint256 allowance) {
        address[6] memory accounts =
            [address(craps), address(game), address(flip), address(coinflip), ContractAddresses.CRAPS_ENGINE, ContractAddresses.JACKPOT_BATTLE];
        uint256 reads;
        uint256 writes;
        for (uint256 i; i < accounts.length; ++i) {
            (bytes32[] memory r, bytes32[] memory w) = vm.accesses(accounts[i]);
            reads += r.length;
            writes += w.length;
        }
        // Explicit read/FIFO authentication and the cold payout module add fixed
        // lifecycle reads. The warm 280k rail covers the measured 268k two-seat path;
        // the complete transaction remains below the current 10M ceiling.
        assertLe(reads, 64, "two-seat field read footprint expanded");
        assertLe(writes, 20, "two-seat field write footprint expanded");
        allowance = reads * 2000 + writes * 2800 + accounts.length * 2600;
        emit log_named_uint("field_cold_storage_reads", reads);
        emit log_named_uint("field_cold_storage_writes", writes);
        emit log_named_uint("field_estimated_transaction_state_allowance", allowance);
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
            uint48 idx = uint48(i & 1);
            _setWord(idx, uint256(keccak256(abi.encode("gas", base, i))));

            uint256 g = gasleft();
            Craps.SlipResult memory small = craps.engineRun(b, idx, stake);
            gasSmall += g - gasleft();

            g = gasleft();
            Craps.SlipResult memory big = craps.engineRun(b, idx, stake * CAP_ROUNDS_TO_SHOOTER_CAP);
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
            3_000_000,
            "a cap-length run regressed past its gas budget"
        );
    }

    /// @dev Gas wins are irrelevant if the production wrapper no longer deploys. Keep a small
    ///      explicit margin under EIP-170's 24,576-byte runtime ceiling; the richer test harness
    ///      itself is intentionally much larger and is not what ships.
    function test_productionRuntimeFitsEip170() public {
        CrapsBattle production = new CrapsBattle();
        emit log_named_uint("CrapsBattle runtime bytes", address(production).code.length);
        // Rail raised 24,400 -> 24,450 (USER 2026-09-23) for the coin draw's craps seats.
        assertLe(address(production).code.length, 24_500, "CrapsBattle runtime left too little deployment headroom");
    }
}
