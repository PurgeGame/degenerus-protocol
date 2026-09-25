// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CoinDrawBattle} from "../../contracts/CoinDrawBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {FlipRoundLib} from "../../contracts/libraries/FlipRoundLib.sol";

/// @dev An independent recomputation of one battle run: the same engine entry, driven with the
///      terms the battle's spec names, so the battle's orchestration (dedupe, units, the bust
///      rule, the pot) is graded against runs it did not compute itself.
contract BattleRef is Craps {
    uint256 internal constant DICE_TAG = 0x436f696e4472617744696365; // "CoinDrawDice"
    uint256 internal constant SCATTER_TAG = 0x436f696e4472617753636174746572; // "CoinDrawScatter"

    function run(uint256 word, address p, uint256 chipFlip) external pure returns (SlipResult memory r) {
        uint256 bankroll = chipFlip * 50 ether;
        Bets memory b;
        _scatterInto(b, uint256(keccak256(abi.encode(word, SCATTER_TAG, uint256(uint160(p))))), chipFlip, 10);
        r = _settleSlip(
            b,
            keccak256(abi.encode(word, DICE_TAG, uint256(uint160(p)))),
            bankroll,
            bankroll * 5,
            22,
            200,
            p,
            0
        );
    }

    /// @dev A raw slip with a caller-chosen hand cap, returning its shape for the gas envelope.
    function capped(uint256 packed, bytes32 seed, uint256 hands, uint256 budget)
        external
        pure
        returns (uint256 h, uint256 rolls)
    {
        Bets memory b = _boardFrom(packed, 1);
        SlipResult memory r = _settleSlip(b, seed, 1e30, 0, hands, budget, address(0xBEEF), 0);
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

contract CoinDrawBattleTest is Test {
    uint256 internal constant ROUND_TAG = 0x436f696e44726177526f756e64; // "CoinDrawRound"

    /// @dev The protocol's two-band award figure, restated.
    function _award(uint256 amount, uint256 entropy) internal pure returns (uint256) {
        if (amount <= 1_000 ether) return (amount / 1 ether) * 1 ether;
        uint256 hundreds = amount / 100 ether;
        uint256 remFlip = (amount % 100 ether) / 1 ether;
        if (remFlip != 0 && uint32(entropy) % 100 < remFlip) ++hundreds;
        return hundreds * 100 ether;
    }

    CoinDrawBattle internal battle;
    BattleRef internal ref;

    function setUp() public {
        battle = new CoinDrawBattle();
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
        vm.prank(ContractAddresses.GAME);
        return battle.resolve(7, e, amount, word);
    }

    function test_OnlyGame() public {
        address[] memory e = _field(3, 1);
        vm.expectRevert(CoinDrawBattle.OnlyGame.selector);
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
        gasBound[0] = gasleft();
        (address[] memory players, uint256[] memory owed) = _resolve(e, amount, word);
        gasBound[0] -= gasleft();

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
        gasBound[1] = RESOLVE_BASE;
        for (uint256 j; j < n; ++j) {
            assertEq(players[j], want[j], "draw order");
            Craps.SlipResult memory r = ref.run(word, want[j], chipFlip);
            gasBound[1] += FIXED + RUN_EXTRA + PER_HAND * r.handsPlayed + PER_ROLL * r.totalRolls;
            assertLe(r.totalRolls, 200, "a run passed the exact roll cap");
            assertLe(r.handsPlayed, 22, "a run passed the hand cap");
            uint256 out = r.stop == Craps.SlipStop.Goal || r.totalRolls >= 200 || r.handsPlayed == 22
                ? r.bankrollOut
                : 0;
            if (out > best) {
                best = out;
                winner = j;
            }
            expect[j] = _award(out * held[j], uint256(keccak256(abi.encode(word, ROUND_TAG, uint256(uint160(want[j]))))));
        }
        if (winner != type(uint256).max) {
            expect[winner] += _award(amount - chipFlip * 50 ether * units, uint256(keccak256(abi.encode(word, ROUND_TAG))));
        }
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
    ///      evaluated at its own hands and rolls, and the model at both caps is the proven bound
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
                Craps.SlipResult memory r = ref.run(word, e[i], chip);
                modelled += FIXED + RUN_EXTRA + PER_HAND * r.handsPlayed + PER_ROLL * r.totalRolls;
            }
            vm.prank(ContractAddresses.GAME);
            uint256 g = gasleft();
            battle.resolve(7, e, amount, word);
            g -= gasleft();
            assertLe(g, modelled, "a field cost more than the composed gas model");
            sum += g;
            if (g > worst) worst = g;
        }
        uint256 proven = RESOLVE_BASE + 50 * (FIXED + RUN_EXTRA + PER_HAND * 22 + PER_ROLL * 200);
        emit log_named_uint("mean gas, 50 entrants", sum / N);
        emit log_named_uint("worst gas, 50 entrants", worst);
        emit log_named_uint("PROVEN resolve bound, 50 entrants at both caps", proven);
        assertLe(proven, 7_350_000, "the proven resolve bound moved");
    }

    /// @dev Gas model of one run: FIXED + PER_HAND x hands + PER_ROLL x rolls, fitted as an upper
    ///      envelope over 3,000 capped runs (least squares plus the largest residual). The proven
    ///      field bound evaluates it at both caps for all 50 entrants; this test re-checks every
    ///      sample against the model on the heaviest board (every leg live) and on random boards
    ///      (both hand machines), on a bankroll deep enough that only the caps stop it, and on
    ///      battle-shaped runs (survival coin, goal latch), so samples span every per-roll path.
    uint256 internal constant FIXED = 10_000;
    uint256 internal constant PER_HAND = 1_100;
    uint256 internal constant PER_ROLL = 480;

    function test_GasEnvelopeProvesTheField() public {
        uint256 board;
        for (uint256 l; l < 10; ++l) board |= uint256(1) << (3 * l);
        uint256 maxHands;
        for (uint256 i; i < 1_500; ++i) {
            uint256 hands = 1 + (i % 22);
            uint256 budget = 1 + ((i * 7) % 200);
            uint256 g = gasleft();
            (uint256 h, uint256 r) = ref.capped(board, keccak256(abi.encode("envelope", i)), hands, budget);
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
            (uint256 h, uint256 r) = ref.capped(packed, keccak256(abi.encode("side", i)), 22, 200);
            g -= gasleft();
            assertLe(g, FIXED + PER_HAND * h + PER_ROLL * r, "a random board cost more than the gas model");
        }
        for (uint256 i; i < 1_500; ++i) {
            uint256 g = gasleft();
            Craps.SlipResult memory r =
                ref.run(uint256(keccak256(abi.encode("shape", i))), address(uint160(i + 1)), 100);
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
        emit log_named_uint("proven dice bound, 50 entrants", field);
        assertLe(field, 6_600_000, "the proven field bound moved");
    }

    /// @dev The hand cap almost never binds: under the battle's own terms, fewer than 0.05% of
    ///      runs reach it (measured 0.004% at 200,000 runs with no cap below 512).
    function test_HandCapAlmostNeverBinds() public {
        uint256 N = 60_000;
        uint256 hit;
        for (uint256 i; i < N; ++i) {
            address p = address(uint160(i + 1));
            Craps.SlipResult memory r = ref.run(uint256(keccak256(abi.encode("tail", i / 50))), p, 60);
            if (r.handsPlayed == 22) ++hit;
        }
        emit log_named_uint("runs reaching the hand cap, per 100k", (hit * 100_000) / N);
        assertLt(hit * 10_000, N * 5, "the hand cap binds on 0.05% of runs or more");
    }
}
