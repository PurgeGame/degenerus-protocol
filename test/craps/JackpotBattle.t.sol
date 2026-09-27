// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {JackpotBattleFieldLib} from "../../contracts/libraries/JackpotBattleFieldLib.sol";
import {CrapsPreferenceStore} from "./CrapsPreferenceStore.sol";

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Craps} from "../../contracts/Craps.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {FlipRoundLib} from "../../contracts/libraries/FlipRoundLib.sol";

/// @dev An independent recomputation of one battle run: the same engine entry, driven with the
///      terms the battle's spec names, so the battle's orchestration (dedupe, units, the bust
///      rule, the pot) is graded against runs it did not compute itself.
contract BattleRef is Craps {
    uint256 internal constant DICE_TAG = 0x436f696e4472617744696365; // "CoinDrawDice"
    uint256 internal constant SCATTER_TAG = 0x436f696e4472617753636174746572; // "CoinDrawScatter"

    /// @dev The scheduled row for a board the dice threw whole: 15% of shooters, +32% profit.
    uint256 internal constant BOOST_ROW = 15 | (32 << 8);

    /// @dev One run at 0-based seat `j` of an `n`-wallet field, its turn in CrapsBattle's form.
    function run(uint256 word, address p, uint256 chipFlip, uint256 j, uint256 n)
        external
        pure
        returns (SlipResult memory r)
    {
        uint256 bankroll = chipFlip * 50 ether;
        Bets memory b;
        _scatterInto(b, uint256(keccak256(abi.encode(word, SCATTER_TAG, uint256(uint160(p))))), chipFlip, 10);
        bytes32 seed = keccak256(abi.encode(word, DICE_TAG));
        uint256 start = uint256(keccak256(abi.encode(ROTATING_SHOOTER_TAG, seed))) % n;
        uint256 offset = ((j + 1) + n - 1 - start) % n;
        r = _settleSlip(b, seed, bankroll, bankroll * 5, 22, 200, p, BOOST_ROW | ((offset + 1) << 16));
    }

    /// @dev Independent canonical decoder and boost lookup, with no production codec use.
    function runBoard(uint256 word, address p, uint256 chipFlip, uint256 j, uint256 n, uint32 chips)
        external pure returns (SlipResult memory r)
    {
        uint256 placed;
        for (uint256 i; i < 10; ++i) placed += (chips >> (i * 3)) & 7;
        uint16[8] memory rows = [uint16(0x200f), 0x1d0e, 0x1d0c, 0x1d0b, 0x1d09, 0x1808, 0x1706, 0x1205];
        Bets memory b = _boardFrom(chips, chipFlip);
        _scatterInto(b, uint256(keccak256(abi.encode(word, SCATTER_TAG, uint256(uint160(p))))), chipFlip, 10 - placed);
        bytes32 seed = keccak256(abi.encode(word, DICE_TAG));
        uint256 start = uint256(keccak256(abi.encode(ROTATING_SHOOTER_TAG, seed))) % n;
        uint256 turn = (j + n - start) % n + 1;
        uint256 bankroll = chipFlip * 50 ether;
        return _settleSlip(b, seed, bankroll, bankroll * 5, 22, 200, p, rows[placed] | (turn << 16));
    }

    /// @dev A raw slip with a caller-chosen hand cap, returning its shape for the gas envelope.
    function capped(uint256 packed, bytes32 seed, uint256 hands, uint256 budget, uint256 turn)
        external
        pure
        returns (uint256 h, uint256 rolls)
    {
        Bets memory b = _boardFrom(packed, 1);
        SlipResult memory r = _settleSlip(b, seed, 1e30, 0, hands, budget, address(0xBEEF), BOOST_ROW | (turn << 16));
        return (r.handsPlayed, r.totalRolls);
    }

    /// @dev A raw slip at a caller-chosen roll budget, for the exact-cap property.
    function slip(uint256 packed, uint256 chipFlip, bytes32 seed, uint256 bankroll, uint256 goal, uint256 budget)
        external
        pure
        returns (SlipResult memory r)
    {
        Bets memory b = _boardFrom(packed, chipFlip);
        r = _settleSlip(b, seed, bankroll, goal, _MAX_SLIP_HANDS, budget, address(0xBEEF), 0);
    }

    /// @dev Sum of the board's stakes, for the cut-hand accounting check.
    function stake(uint256 packed, uint256 chipFlip) external pure returns (uint256) {
        return _stakeFor(_boardFrom(packed, chipFlip));
    }
}

contract JackpotBattleMultiplierHarness is JackpotBattle {
    function multiplierBps(uint256 entropy) external pure returns (uint256) {
        return _multiplierBps(entropy);
    }
}

contract JackpotBattleMultiplierDistributionTest is Test {
    function test_AllThousandBucketsHaveMeanOneAndExactTierCounts() public {
        JackpotBattleMultiplierHarness h = new JackpotBattleMultiplierHarness();
        uint256[4] memory counts;
        uint256 sum;
        for (uint256 i; i < 1_000; ++i) {
            uint256 m = h.multiplierBps(i);
            // An independent table pins the boundaries as well as the bucket totals.
            uint256 want = i >= 999 ? 1_000_000 : i >= 990 ? 200_000 : i >= 900 ? 30_000 : 5_000;
            assertEq(m, want);
            ++counts[m == 5_000 ? 0 : m == 30_000 ? 1 : m == 200_000 ? 2 : 3];
            sum += m;
        }
        assertEq(counts[0], 900); assertEq(counts[1], 90);
        assertEq(counts[2], 9); assertEq(counts[3], 1);
        assertEq(sum, 1_000 * 10_000, "expected multiplier must be 1x");
    }
}

contract JackpotBattleTest is Test {
    uint256 internal constant ROUND_TAG = 0x436f696e44726177526f756e64; // "CoinDrawRound"
    uint256 internal constant MULTIPLIER_TAG = 0x436f696e447261774d756c7469706c696572;

    function _multiplier(uint256 word) private pure returns (uint256) {
        uint256 roll = uint256(keccak256(abi.encode(word, MULTIPLIER_TAG))) % 1_000;
        return roll == 999 ? 1_000_000 : roll >= 990 ? 200_000 : roll >= 900 ? 30_000 : 5_000;
    }

    /// @dev The protocol's two-band award figure, restated.
    function _award(uint256 amount, uint256 entropy) internal pure returns (uint256) {
        if (amount <= 1_000 ether) return (amount / 1 ether) * 1 ether;
        uint256 hundreds = amount / 100 ether;
        uint256 remFlip = (amount % 100 ether) / 1 ether;
        if (remFlip != 0 && uint32(entropy) % 100 < remFlip) ++hundreds;
        return hundreds * 100 ether;
    }

    JackpotBattle internal battle;
    BattleRef internal ref;
    mapping(address => uint32) private selected;

    function setUp() public {
        vm.etch(ContractAddresses.CRAPS, address(new CrapsPreferenceStore()).code);
        battle = new JackpotBattle();
        ref = new BattleRef();
    }

    function _field(uint256 n, uint256 salt) internal pure returns (address[] memory e) {
        e = new address[](n);
        for (uint256 i; i < n; ++i) {
            e[i] = address(uint160(uint256(keccak256(abi.encode(salt, i)))));
        }
    }

    function _resolve(address[] memory e, uint256 amount, uint256 word)
        internal
        returns (address[] memory players, uint256[] memory owed)
    {
        uint256[] memory field = JackpotBattleFieldLib.prepare(e, amount);
        vm.prank(ContractAddresses.GAME);
        (players, owed,,,) = battle.resolve(7, field, amount, word);
    }

    function _select(address p, uint32 chips) private {
        uint256 compact;
        for (uint256 i; i < 10; ++i) compact |= uint256((chips >> (i * 3)) & 7) << (i * 2);
        vm.store(ContractAddresses.CRAPS, keccak256(abi.encode(p, uint256(15))), bytes32((compact << 64) | (1 << 84)));
        selected[p] = chips;
    }

    function _validBoard(uint256 entropy) private pure returns (uint32 chips) {
        uint256 remaining = entropy % 8;
        bool dark = entropy & 8 != 0;
        for (uint256 i; i < 10; ++i) {
            uint256 count = (entropy >> (8 + i * 2)) & 3;
            if ((dark && i == 0) || (!dark && i == 9)) count = 0;
            if (count > remaining) count = remaining;
            remaining -= count;
            chips |= uint32(count << (i * 3));
        }
    }

    function testFuzz_SavedBoardsPayByTheRules(uint256 word, uint8 repeat, uint256 amount) public {
        address[] memory e = _field(50, word);
        uint256 distinct = bound(repeat, 1, 50);
        for (uint256 i; i < 50; ++i) {
            e[i] = address(uint160((i % distinct) << 8));
            _select(e[i], _validBoard(uint256(keccak256(abi.encode(word, i % distinct)))));
        }
        _assertFieldPaysByTheRules(e, bound(amount, 450, 1e12) * 1 ether, word);
    }

    function test_LookupsOnlyDistinctPlayedWalletsAndEventSnapshot() public {
        address[] memory e = new address[](4);
        e[0] = address(10); e[1] = e[0]; e[2] = address(20); e[3] = address(30);
        uint32 board = (3 << 27) | (3 << 12) | (1 << 15);
        _select(e[0], board);
        bytes32[] memory slots = new bytes32[](1);
        slots[0] = keccak256(abi.encode(e[0], uint256(15)));
        vm.expectCall(ContractAddresses.CRAPS, abi.encodeWithSignature("extsload(bytes32[])", slots), uint64(1));
        vm.record();
        vm.recordLogs();
        _resolve(e, 900 ether, 77); // two units, one distinct wallet
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("JackpotBattleRun(uint24,address,uint256,uint256,uint256,uint256,uint32)");
        uint256 events;
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == topic) {
            (uint256 units,,,,uint32 played) = abi.decode(logs[i].data, (uint256,uint256,uint256,uint256,uint32));
            assertEq(units, 2); assertEq(played, board); ++events;
        }
        assertEq(events, 1);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(ContractAddresses.CRAPS);
        assertEq(writes.length, 0, "coin draw mutated preferences");
        assertEq(reads.length, 1, "must only read the one distinct played wallet");
        assertEq(reads[0], slots[0]);
    }

    function test_FieldPackingMasksOtherPassCreditFields() public {
        address[] memory entrants = new address[](3);
        entrants[1] = address(0x100); // same low-byte collision as address(0)
        uint32 board = (3 << 27) | (3 << 12) | (1 << 15);
        _select(address(0), board);
        bytes32 slot = keccak256(abi.encode(address(0), uint256(15)));
        uint256 noise = (type(uint256).max << 85) | type(uint64).max;
        vm.store(ContractAddresses.CRAPS, slot, bytes32(uint256(vm.load(ContractAddresses.CRAPS, slot)) | noise));
        uint256[] memory field = JackpotBattleFieldLib.prepare(entrants, 150_000 ether);
        assertEq(field.length, 2);
        assertEq(uint160(field[0]), 0); assertEq(field[0] >> 180, 2);
        assertEq(uint160(field[1]), 0x100); assertEq(field[1] >> 180, 1);
        uint256 compact = (field[0] >> 160) & 0xfffff;
        uint256 canonical;
        for (uint256 leg; leg < 10; ++leg) canonical |= ((compact >> (2 * leg)) & 3) << (3 * leg);
        assertEq(canonical, board);
        assertEq((field[1] >> 160) & 0xfffff, 0);
    }

    function test_BattleUsesPassedSnapshotWithoutCallbacks() public {
        address[] memory e = _field(3, 31);
        _select(e[0], 3 | (3 << 12) | (1 << 15));
        uint256[] memory field = JackpotBattleFieldLib.prepare(e, 150_000 ether);
        // Once prepared, neither changed storage nor an unavailable reader can affect resolve.
        _select(e[0], 0);
        vm.mockCallRevert(ContractAddresses.CRAPS, bytes(""), "unexpected callback");
        vm.record();
        vm.prank(ContractAddresses.GAME);
        (address[] memory players,,,,) = battle.resolve(7, field, 150_000 ether, 31);
        assertEq(players, e);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(ContractAddresses.CRAPS);
        assertEq(reads.length, 0);
        assertEq(writes.length, 0);
    }

    function test_NoAffordableEntriesSkipsReader() public {
        vm.mockCallRevert(ContractAddresses.CRAPS, bytes(""), "unexpected read");
        vm.recordLogs();
        (address[] memory players,) = _resolve(_field(50, 1), 449 ether, 99);
        assertEq(players.length, 0);
        (players,) = _resolve(new address[](0), 150_000 ether, 99);
        assertEq(players.length, 0);
        assertEq(vm.getRecordedLogs().length, 0, "empty fields must not emit a multiplier");
    }

    function test_AllMultiplierTiersScaleRunsAndPotBeforeRounding() public {
        uint256[4] memory tiers = [uint256(5_000), 30_000, 200_000, 1_000_000];
        address[] memory e = _field(50, 123);
        e[1] = e[0]; e[3] = e[2]; // the same roll also scales repeated entry units
        for (uint256 i; i < 50; ++i) _select(e[i], _validBoard(i * 7919));
        for (uint256 t; t < tiers.length; ++t) {
            uint256 word;
            while (_multiplier(word) != tiers[t]) ++word;
            // Exercise both rounding bands, fractional-FLIP pot dust and the uint24 chip clamp.
            _assertFieldPaysByTheRules(e, 451.75 ether, word);
            _assertFieldPaysByTheRules(e, 150_001.75 ether, word);
            _assertFieldPaysByTheRules(e, uint256(type(uint128).max), word);
        }
    }

    function test_GasSavedBoardFields() public {
        for (uint256 count; count < 8; ++count) {
            address[] memory e = _field(50, count);
            // Cover all boost rows, both pass sides, late legs, and dense seven-chip boards.
            for (uint256 i; i < 50; ++i) {
                uint256 side = i % 2 == 0 ? 0 : 27;
                uint32 chips = uint32((count > 3 ? 3 : count) << side);
                if (count > 3) chips |= uint32((count > 6 ? 3 : count - 3) << 12);
                if (count > 6) chips |= 1 << 24;
                _select(e[i], chips);
            }
            // vm.store warms storage; cool it to measure the actual cold reader path.
            vm.cool(ContractAddresses.CRAPS);
            for (uint256 i; i < 50; ++i) vm.coolSlot(ContractAddresses.CRAPS, keccak256(abi.encode(e[i], uint256(15))));
            _assertFieldPaysByTheRules(e, 150_000 ether, uint256(keccak256(abi.encode(count))));
        }
    }

    function test_OnlyGame() public {
        uint256[] memory e = new uint256[](3);
        vm.expectRevert(JackpotBattle.OnlyGame.selector);
        battle.resolve(7, e, 100_000 ether, 1);
    }

    /// @dev Every rule against an independent recomputation: repeats fold into units in draw
    ///      order, a bust pays nothing, a run stopped by either cap or latched at the goal pays its bankroll times its
    ///      units on the two-band award figure, and the pot goes to the highest paid ending bankroll, the
    ///      earlier-drawn wallet on a tie.
    function testFuzz_FieldPaysByTheRules(uint256 word, uint256 amountFlip, uint8 dupEvery) public {
        amountFlip = bound(amountFlip, 5_000, 1e12);
        uint256 amount = amountFlip * 1 ether + (word % 1 ether);
        address[] memory e = _field(50, word);
        uint256 d = bound(dupEvery, 2, 9);
        for (uint256 i = d; i < 50; i += d) e[i] = e[i - d / 2 - 1];

        _assertFieldPaysByTheRules(e, amount, word);
    }

    function testFuzz_CollidingWalletsPayByTheRules(uint256 word, uint8 repetitions) public {
        address[] memory e = new address[](50);
        uint256 distinct = bound(repetitions, 1, 50);
        for (uint256 i; i < e.length; ++i) e[i] = address(uint160((i % distinct) << 8));
        _assertFieldPaysByTheRules(e, 150_000 ether, word);
    }

    function _assertFieldPaysByTheRules(address[] memory e, uint256 amount, uint256 word) private {
        uint256[2] memory gasBound;
        vm.recordLogs();
        gasBound[0] = gasleft();
        uint256[] memory field = JackpotBattleFieldLib.prepare(e, amount);
        vm.prank(ContractAddresses.GAME);
        (address[] memory players, uint256[] memory owed, address jackpotWinner, uint256 peak, uint256 score) =
            battle.resolve(7, field, amount, word);
        gasBound[0] -= gasleft();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs[0].emitter, address(battle));
        assertEq(logs[0].topics[0], keccak256("JackpotBattleMultiplier(uint24,uint256,uint256)"));
        assertEq(uint256(logs[0].topics[1]), 7);
        (uint256 baseBudget, uint256 rolledBps) = abi.decode(logs[0].data, (uint256,uint256));
        assertEq(baseBudget, amount);
        assertEq(rolledBps, _multiplier(word));

        uint256 stakes = (amount * 2) / 3;
        uint256 units = e.length;
        if (units > stakes / 300 ether) units = stakes / 300 ether;
        uint256 chipFlip = (stakes / units / 300 ether) * 6;
        if (chipFlip > (type(uint24).max / 10 / 6) * 6) chipFlip = (type(uint24).max / 10 / 6) * 6;
        assertEq((chipFlip * 50 ether) % 300 ether, 0, "a bankroll off the 300-FLIP granule");

        // Rebuild the distinct field and its units from the truncated draw.
        address[] memory want = new address[](units);
        uint256[] memory held = new uint256[](units);
        uint256 n;
        for (uint256 i; i < units; ++i) {
            uint256 j;
            while (j < n && want[j] != e[i]) ++j;
            if (j == n) want[n++] = e[i];
            ++held[j];
        }
        assertEq(players.length, n, "distinct count");
        assertEq(owed.length, n, "owed length");

        uint256 best;
        uint256 winner = type(uint256).max;
        uint256[] memory expect = new uint256[](n);
        uint256 wantPeak;
        uint256 multiplier = _multiplier(word);
        gasBound[1] = RESOLVE_BASE;
        for (uint256 j; j < n; ++j) {
            assertEq(players[j], want[j], "draw order");
            Craps.SlipResult memory r = ref.runBoard(word, want[j], chipFlip, j, n, selected[want[j]]);
            (uint256 loggedUnits, uint256 loggedBankroll, uint256 loggedRolls, uint256 loggedPaid,) =
                abi.decode(logs[j + 1].data, (uint256,uint256,uint256,uint256,uint32));
            assertEq(loggedUnits, held[j]);
            assertEq(loggedBankroll, r.bankrollOut, "multiplier changed simulated bankroll");
            assertEq(loggedRolls, r.totalRolls, "multiplier changed dice work");
            gasBound[1] += FIXED + RUN_EXTRA + PER_HAND * r.handsPlayed + PER_ROLL * r.totalRolls;
            assertLe(r.totalRolls, 200, "a run passed the exact roll cap");
            assertLe(r.handsPlayed, 22, "a run passed the hand cap");
            uint256 out = r.stop == Craps.SlipStop.Goal || r.totalRolls >= 200 || r.handsPlayed == 22
                ? r.bankrollOut
                : 0;
            if (out > best) {
                best = out;
                winner = j;
                wantPeak = r.stop == Craps.SlipStop.Goal ? r.peakBankroll / 1 ether : 0;
            }
            expect[j] = _award(out * held[j] * multiplier / 10_000, uint256(keccak256(abi.encode(word, ROUND_TAG, uint256(uint160(want[j]))))));
            assertEq(loggedPaid, expect[j], "run event must report multiplied, rounded payment");
        }
        if (winner != type(uint256).max) {
            uint256 pot = _award((amount - chipFlip * 50 ether * units) * multiplier / 10_000, uint256(keccak256(abi.encode(word, ROUND_TAG))));
            expect[winner] += pot;
            assertEq(logs[n + 1].topics[0], keccak256("JackpotBattlePot(uint24,address,uint256)"));
            assertEq(abi.decode(logs[n + 1].data, (uint256)), pot);
        }
        assertEq(jackpotWinner, winner == type(uint256).max ? address(0) : want[winner], "jackpot candidate must be pot winner");
        assertEq(peak, wantPeak, "winner's qualifying high point");
        assertEq(score, wantPeak * 10_000 / (chipFlip * 50), "unmultiplied peak score");
        for (uint256 j; j < n; ++j) assertEq(owed[j], expect[j], "owed");
        assertLe(gasBound[0], gasBound[1], "field exceeds the gas model, including colliding wallets");
    }

    /// @dev A budget that cannot give every drawn unit the 300-FLIP floor plays fewer, from the
    ///      front; one that cannot give even one pays nothing and returns empty.
    function test_SmallBudgetPlaysFewerUnits() public {
        address[] memory e = _field(50, 3);
        (address[] memory players,) = _resolve(e, 4_500 ether, 11);
        assertEq(players.length, 10, "3,000 FLIP of stakes (two thirds) seats ten 300-FLIP bankrolls");
        (players,) = _resolve(e, 449 ether, 11);
        assertEq(players.length, 0, "under one bankroll plays nobody");
    }

    /// @dev A roll budget under one hand is exact: no run passes it, whatever the board.
    function testFuzz_SubHandBudgetIsExact(bytes32 seed, uint32 packed, uint256 budget) public view {
        budget = bound(budget, 1, 511);
        uint256 board = uint256(packed) & ((1 << 30) - 1);
        if (ref.stake(board, 10) == 0) board = 1;
        Craps.SlipResult memory r = ref.slip(board, 10, seed, 1_000_000 ether, 0, budget);
        assertLe(r.totalRolls, budget, "rolls passed an exact budget");
    }

    /// @dev The shipped 8,192 budget is a between-shooters budget, as before: a hand it admits
    ///      still runs whole, so its runs can pass the budget by up to one hand.
    function test_FullBudgetKeepsItsMeaning() public view {
        uint256 over;
        for (uint256 i; i < 40 && over == 0; ++i) {
            Craps.SlipResult memory r = ref.slip(1, 10, keccak256(abi.encode(i)), 1_000_000 ether, 0, 20);
            // 20 < 512 is exact now; the between-shooters meaning is kept at >= _MAX_ROLLS.
            assertLe(r.totalRolls, 20);
            r = ref.slip(1, 10, keccak256(abi.encode(i)), 1e30, 0, 512);
            if (r.totalRolls > 512) over = r.totalRolls;
        }
        assertGt(over, 512, "a 512 budget no longer lets its last hand finish");
    }

    /// @dev Everything `resolve` does beyond one run's dice (scatter, keys, event, award) and the
    ///      field's own base (dedupe, arrays, the call). Checked below as an upper bound on every
    ///      real field, alongside the per-run dice model, so the composition bounds `resolve`.
    uint256 internal constant RESOLVE_BASE = 300_000;
    uint256 internal constant RUN_EXTRA = 10_000;

    /// @dev Real 50-wallet fields over many words: each costs no more than the composed model
    ///      evaluated at its own hands and rolls, and the model at both caps is the model bound
    ///      on `resolve` that the purchase-day advance's worst case is sized against.
    function test_GasFiftyEntrants() public {
        uint256 worst;
        uint256 sum;
        uint256 N = 150;
        for (uint256 w; w < N; ++w) {
            address[] memory e = _field(50, w + 1000);
            uint256 word = uint256(keccak256(abi.encode("word", w)));
            uint256 amount = (5_000 + (w * 7919) % 5_000_000) * 1 ether;
            uint256 modelled = RESOLVE_BASE;
            uint256 chip = ((amount * 2) / 3 / 50 / 300 ether) * 6;
            for (uint256 i; i < 50; ++i) {
                Craps.SlipResult memory r = ref.run(word, e[i], chip, i, 50);
                modelled += FIXED + RUN_EXTRA + PER_HAND * r.handsPlayed + PER_ROLL * r.totalRolls;
            }
            uint256 g = gasleft();
            _resolve(e, amount, word);
            g -= gasleft();
            assertLe(g, modelled, "a field cost more than the composed gas model");
            sum += g;
            if (g > worst) worst = g;
        }
        uint256 model = RESOLVE_BASE + 50 * (FIXED + RUN_EXTRA + PER_HAND * 22 + PER_ROLL * 200);
        emit log_named_uint("mean gas, 50 entrants", sum / N);
        emit log_named_uint("worst gas, 50 entrants", worst);
        emit log_named_uint("MODEL resolve bound, 50 entrants at both caps", model);
        assertLe(model, 7_475_000, "the model resolve bound moved");
    }

    /// @dev Gas model of one run: FIXED + PER_HAND x hands + PER_ROLL x rolls, fitted as an upper
    ///      envelope over 3,000 capped runs (least squares plus the largest residual). The model
    ///      field bound evaluates it at both caps for all 50 entrants; this test re-checks every
    ///      sample against the model on the heaviest board (every leg live) and on random boards
    ///      (both hand machines), on a bankroll deep enough that only the caps stop it, and on
    ///      battle-shaped runs (survival coin, goal latch), so samples span every per-roll path.
    uint256 internal constant FIXED = 10_000;
    uint256 internal constant PER_HAND = 1_250;
    uint256 internal constant PER_ROLL = 480;

    function test_GasEnvelopeProvesTheField() public {
        uint256 board;
        for (uint256 l; l < 10; ++l) board |= uint256(1) << (3 * l);
        uint256 maxHands;
        for (uint256 i; i < 1_500; ++i) {
            uint256 hands = 1 + (i % 22);
            uint256 budget = 1 + ((i * 7) % 200);
            uint256 g = gasleft();
            (uint256 h, uint256 r) = ref.capped(board, keccak256(abi.encode("envelope", i)), hands, budget, 1 + i % 22);
            g -= gasleft();
            assertLe(g, FIXED + PER_HAND * h + PER_ROLL * r, "a run cost more than the gas model");
            if (h > maxHands) maxHands = h;
        }
        assertEq(maxHands, 22, "the samples never reached the hand cap");
        // Every other per-roll path: random boards (about a third have no pass line and run the
        // side machine) on the deep bankroll, and battle-shaped runs on a real five-deep bankroll
        // (the survival coin and the goal latch), all at both caps.
        for (uint256 i; i < 1_500; ++i) {
            uint256 packed = uint256(keccak256(abi.encode("board", i))) & ((1 << 30) - 1);
            if (packed == 0) packed = 1 << 27;
            uint256 g = gasleft();
            (uint256 h, uint256 r) = ref.capped(packed, keccak256(abi.encode("side", i)), 22, 200, 1 + i % 22);
            g -= gasleft();
            assertLe(g, FIXED + PER_HAND * h + PER_ROLL * r, "a random board cost more than the gas model");
        }
        for (uint256 i; i < 1_500; ++i) {
            uint256 g = gasleft();
            Craps.SlipResult memory r =
                ref.run(uint256(keccak256(abi.encode("shape", i))), address(uint160(i + 1)), 100, i % 50, 50);
            g -= gasleft();
            // `run` also scatters the board and derives both seeds: the work RUN_EXTRA carries in
            // the composed bound, so these samples are held to the per-run figure it charges.
            assertLe(
                g,
                FIXED + RUN_EXTRA + PER_HAND * r.handsPlayed + PER_ROLL * r.totalRolls,
                "a battle run cost more than the gas model"
            );
        }
        uint256 field = 50 * (FIXED + PER_HAND * 22 + PER_ROLL * 200);
        emit log_named_uint("model dice bound, 50 entrants", field);
        assertLe(field, 6_675_000, "the model field bound moved");
    }

    /// @dev The hand cap almost never binds: under the battle's own terms, fewer than 0.05% of
    ///      runs reach it (measured 0.0095% at 200,000 runs with no cap below 512).
    function test_HandCapAlmostNeverBinds() public {
        uint256 N = 60_000;
        uint256 hit;
        for (uint256 i; i < N; ++i) {
            address p = address(uint160(i + 1));
            Craps.SlipResult memory r = ref.run(uint256(keccak256(abi.encode("tail", i / 50))), p, 60, i % 50, 50);
            if (r.handsPlayed == 22) ++hit;
        }
        emit log_named_uint("runs reaching the hand cap, per 100k", (hit * 100_000) / N);
        assertLt(hit * 10_000, N * 5, "the hand cap binds on 0.05% of runs or more");
    }
}
