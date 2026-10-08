// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import "forge-std/Test.sol";
import {CrapsViews} from "../craps/CrapsViews.sol";
import {Craps} from "../../contracts/Craps.sol";

/// @title Craps arithmetic — symbolic properties over the table's pure helpers.
/// @notice The craps table's money arithmetic is a handful of pure functions: the basis-point
///         pool share every progressive rung pays through, the ladder/progressive split of a
///         day's budget, the boon settlement bonus with its 60k base cap,
///         the shooter-boost table decode, the tier draw and its 4:2:1 weight, the stake
///         of a board, and the saturating won-component. The `check_` properties hold for EVERY
///         input in their domain (symbolic); the `testFuzz_` properties are the nonlinear
///         ones (a product bracketed by a division, two monotonicities in a product's factor) that
///         time out on z3 and yices at 256-bit width, so forge fuzzes them instead. Run with:
///           FOUNDRY_PROFILE=halmos halmos --match-contract '^CrapsArithmeticSymbolicTest$' \
///             --forge-build-out forge-out-halmos --loop 8 --solver yices --solver-timeout-assertion 120000
contract CrapsArithmeticSymbolicTest is Test {
    CrapsViews internal craps;

    uint256 internal constant BPS = 10_000;
    uint256 internal constant BOON_CAP = 60_000; // whole FLIP, matching settlement units
    uint256 internal constant WON_MASK = 0xFFFFFFFFFFF;

    function setUp() public {
        craps = new CrapsViews();
    }

    // ------------------------------------------------------------------------------------
    // _poolShare: divide-first is EXACTLY floor(pool * bps / 10_000), and never exceeds the pool.
    // ------------------------------------------------------------------------------------

    function testFuzz_poolShare_isExactFloor(uint128 pool, uint16 bps) public view {
        vm.assume(bps <= BPS);
        uint256 share = craps.poolShareOf(pool, bps);
        // floor(pool * bps / BPS) stated without a symbolic division: the share times the
        // denominator brackets the product within one denominator.
        uint256 product = uint256(pool) * bps;
        assert(share * BPS <= product);
        assert(product < share * BPS + BPS);
        assert(share <= pool);
    }

    function testFuzz_poolShare_monotoneInBps(uint128 pool, uint16 lo, uint16 hi) public view {
        vm.assume(lo <= hi && hi <= BPS);
        assert(craps.poolShareOf(pool, lo) <= craps.poolShareOf(pool, hi));
    }

    // ------------------------------------------------------------------------------------
    // _splitMainBudget: the two halves conserve the budget and differ by at most one wei.
    // ------------------------------------------------------------------------------------

    function check_splitMainBudget_conserves(uint256 rawMain) public view {
        (uint256 ladder, uint256 progressive) = craps.splitMainBudget(rawMain);
        assert(ladder + progressive == rawMain);
        assert(progressive >= ladder);
        assert(progressive - ladder <= 1);
    }

    // ------------------------------------------------------------------------------------
    // _boonBonus: zero off the three tiers, capped by the 60k base, monotone below the cap.
    // ------------------------------------------------------------------------------------

    /// @custom:halmos --solver cvc5-int
    function check_boonBonus_capAndTiers(uint256 mask, uint256 basePaid) public view {
        uint256 bonus = craps.boonBonusOf(mask, basePaid);
        if (mask != 1 && mask != 2 && mask != 4) {
            assert(bonus == 0);
        } else {
            uint256 bps = mask == 1 ? 500 : (mask == 2 ? 1000 : 1500);
            uint256 base = basePaid > BOON_CAP ? BOON_CAP : basePaid;
            assert(bonus == (base * bps) / BPS);
            assert(bonus <= (BOON_CAP * 1500) / BPS);
        }
    }

    function testFuzz_boonBonus_monotoneBelowCap(uint8 mask, uint96 a, uint96 b) public view {
        vm.assume(a <= b && b <= BOON_CAP);
        assert(craps.boonBonusOf(mask, a) <= craps.boonBonusOf(mask, b));
    }

    function test_boonCapUnitsAndBoundaryReplays() public view {
        assertEq(craps.BOON_PAYOUT_BASE_CAP(), BOON_CAP);
        for (uint256 mask; mask <= 8; ++mask) {
            check_boonBonus_capAndTiers(mask, 0);
            check_boonBonus_capAndTiers(mask, BOON_CAP - 1);
            check_boonBonus_capAndTiers(mask, BOON_CAP);
            check_boonBonus_capAndTiers(mask, BOON_CAP + 1);
            check_boonBonus_capAndTiers(mask, uint256(1) << 67);
            check_boonBonus_capAndTiers(mask, type(uint256).max);
        }
    }

    // ------------------------------------------------------------------------------------
    // _shooterBoostTerms: hot profit starts after roll12, with the approved duration rates.
    // ------------------------------------------------------------------------------------

    function check_shooterBoostTerms_table(uint256 placed) public view {
        vm.assume(placed < 16);
        uint256 t = craps.shooterBoostTerms(placed);
        uint256 threshold = t & 0xFF;
        uint256 rate = t >> 8;
        if (placed >= 8) {
            assert(t == 0);
        } else {
            // Explicit branches keep the independent rows readable and avoid symbolic
            // memory indexing, which this Halmos version does not implement.
            uint256 expectedRate = placed == 0 ? 30 : placed == 1 ? 25 : placed == 2 ? 20
                : placed == 3 ? 18 : placed == 4 ? 14 : placed == 5 ? 10 : placed == 6 ? 7 : 5;
            assert(threshold == 12);
            assert(rate == expectedRate);
            // Threshold stays fixed; the hot-profit rate falls with placed chips.
            if (placed < 7) {
                uint256 n = craps.shooterBoostTerms(placed + 1);
                assert((n & 0xFF) == threshold);
                assert((n >> 8) <= rate);
            }
        }
    }

    // ------------------------------------------------------------------------------------
    // _tierPick / _routineWeight: five ordinary windows, each with weight 1, 2 or 4.
    // The separately funded jackpot is excluded. Matching bookends share their tier.
    // ------------------------------------------------------------------------------------

    function check_tierPick_inRange(uint256 word, uint256 period) public view {
        vm.assume(period < 7);
        assert(craps.tierPickAt(word, period) <= 2);
    }

    function check_routineWeight_bounds(uint256 word) public view {
        uint256 w = craps.routineWeightOf(word);
        assert(w >= 5 && w <= 20);
    }

    function check_routineWeight_matchesFiveWindowPricing(uint256 word) public view {
        assert(craps.BONUS_PERIODS_PER_DAY() == 6);
        uint256 bookendTier = craps.tierPickAt(word, 0);
        assert(craps.tierPickAt(word, 4) == bookendTier);
        uint256 expected = 2 * (1 << bookendTier);
        expected += 1 << craps.tierPickAt(word, 1);
        expected += 1 << craps.tierPickAt(word, 2);
        expected += 1 << craps.tierPickAt(word, 3);
        assert(craps.routineWeightOf(word) == expected);
    }

    /// @dev Concrete keccak replays accompany the symbolic hash abstraction. The original
    ///      solver model selected word 0, but its abstract hash values are not a real preimage:
    ///      actual word 0 has weight 9. Word 36 really reaches the former bound's violation.
    function test_routineWeightConcreteBoundaries() public view {
        assertEq(craps.routineWeightOf(0), 9);
        assertEq(craps.routineWeightOf(36), 5);
        assertEq(craps.routineWeightOf(537), 20);
    }

    function test_shooterBoostAllRows() public view {
        for (uint256 placed; placed < 16; ++placed) check_shooterBoostTerms_table(placed);
        assertEq(craps.shooterBoostTerms(7), (5 << 8) | 12);
    }

    // ------------------------------------------------------------------------------------
    // _stakeFor: the stake is exactly the chip total in whole FLIP.
    // ------------------------------------------------------------------------------------

    /// @custom:halmos --solver cvc5-int
    function check_stakeFor_isChipTotal(
        uint24 passLine,
        uint24 place4,
        uint24 place5,
        uint24 place6,
        uint24 place8,
        uint24 place9,
        uint24 place10,
        uint24 hard4,
        uint24 hard8,
        uint24 dontPass
    ) public view {
        Craps.Bets memory b = Craps.Bets({
            passLine: passLine,
            place4: place4,
            place5: place5,
            place6: place6,
            place8: place8,
            place9: place9,
            place10: place10,
            hard4: hard4,
            hard8: hard8,
            dontPass: dontPass
        });
        uint256 chips = uint256(passLine) + place4 + place5 + place6 + place8 + place9 + place10 + hard4 + hard8
            + dontPass;
        // Prove the widening bound before multiplying; this is an assertion, not an assumption.
        assert(chips <= uint256(type(uint24).max) * 10);
        uint256 expected;
        // The proved bound makes this product exact. A constant-divisor round trip verifies it
        // without solc's symbolic-divisor overflow predicate overwhelming the SMT solver.
        unchecked { expected = chips * 1 ether; }
        assert(expected / 1 ether == chips);
        assert(craps.stakeFor(b) == expected);
    }

    // ------------------------------------------------------------------------------------
    // _wonComponent: whole FLIP, saturating at the scoreboard field width.
    // ------------------------------------------------------------------------------------

    function check_wonComponent_saturates(uint256 won) public view {
        uint256 f = craps.wonComponentOf(won);
        assert(f <= WON_MASK);
        if (won / 1 ether <= WON_MASK) assert(f == won / 1 ether);
        else assert(f == WON_MASK);
    }
}
