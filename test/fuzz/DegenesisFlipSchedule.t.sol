// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DegenesisHarness} from "./helpers/DegenesisHarness.sol";
import {FlipRoundLib} from "../../contracts/libraries/FlipRoundLib.sol";

/// @title DegenesisFlipSchedule -- FLIP day schedule, early bonus and volume factor (spec §5, check 7)
/// @notice FLIP = ladder x base(n)/2 x earlyBonus(s) x K/(K + V) at the level-1 conversion price,
///         base(n) = 2.5 - 0.125(n - 1), earlyBonus = 1 + 0.05 max(0, 1 - s/21,600 s), K = 46 ETH.
///         Spec expectations here are computed in a separate decimal route (milli / ppm / WAD
///         fixed point) from the reference model, and the driven contract results are checked
///         against both.
contract DegenesisFlipSchedule is DegenesisHarness {
    address internal a;
    address internal b;
    address internal c3;
    address internal d4;

    /// @dev Exact ladder mean in tenths of a bps: (16 x 22,783 + 4 x 108,869) / 20 = 40,000.2.
    uint256 internal constant LADDER_MEAN_DECI_BPS = 400_002;

    function setUp() public override {
        super.setUp();
        a = _player("fs-a");
        b = _player("fs-b");
        c3 = _player("fs-c");
        d4 = _player("fs-d");
        _drive(0);
        _earnCredit(a, 200 ether);
        _earnCredit(b, 5 ether);
        _earnCredit(c3, 5 ether);
        _earnCredit(d4, 5 ether);
        _driveDay(2, 0);
    }

    // ---- independent spec route ----

    /// @dev base(n) in milli: 2500 - 125 (n - 1).
    function _baseMilli(uint256 n) internal pure returns (uint256) {
        return 2500 - 125 * (n - 1);
    }

    /// @dev earlyBonus in ppm: 1e6 + 50,000 x max(0, 1 - s / 21,600), floored.
    function _bonusPpm(uint256 s) internal pure returns (uint256) {
        if (s >= 21_600) return 1_000_000;
        return 1_000_000 + (50_000 * (21_600 - s)) / 21_600;
    }

    /// @dev rWad = K x 1e18 / (K + V), over wei.
    function _rWad(uint256 vWei) internal pure returns (uint256) {
        return (46 ether * 1e18) / (46 ether + vWei);
    }

    /// @dev Spec FLIP for x wei at `bps` (conditional branch), before rounding:
    ///      x x bps/1e4 x base/2 x bonus x r / (0.01 ETH per 1,000 FLIP).
    function _specFlip(uint256 xWei, uint256 bps, uint256 n, uint256 s, uint256 vWei) internal pure returns (uint256) {
        return (xWei * bps * _baseMilli(n) * _bonusPpm(s) / 1e4 / 2 / 1000 * _rWad(vWei) / 1e18 / 1e6) * 1000 / 0.01 ether;
    }

    /// @notice Spec table: the overall nominal mean (half the conditional ladder mean) is
    ///         base(n) x earlyBonus at opening, three hours, six hours and later, every day.
    function test_SpecTableMeansAtBonusTimes() public pure {
        uint256[7] memory opening = [uint256(2625), 2494, 2363, 2231, 2100, 1969, 1838];
        uint256[4] memory times = [uint256(0), 10_800, 21_600, 40_000];
        for (uint256 n = 1; n <= 7; ++n) {
            for (uint256 t; t < 4; ++t) {
                uint256 s = times[t];
                // Reference FLIP for 1 ETH at the nominal 4x branch mean (40,000 bps), V -> 0.
                uint256 raw = _refFlipRaw(10_000, 40_000, n, s, 0);
                // Overall mean in milli-x of purchase value: FLIP x 0.01 ETH / 1,000 / 1 ETH / 2.
                uint256 meanMicro = raw * 1e6 / 1e5 / 2; // 1e5 FLIP = 1 ETH of value
                uint256 specMicro = _baseMilli(n) * _bonusPpm(s) / 1000;
                assertApproxEqAbs(meanMicro, specMicro, 1, "mean = base x bonus");
                if (t == 0) assertApproxEqAbs(specMicro / 1000, opening[n - 1], 1, "table opening mean");
                if (t == 1) assertEq(_bonusPpm(s), 1_025_000, "+2.5% at 3h");
                if (t >= 2) assertEq(raw, 25_000 * (21 - n), "no bonus from 6h: 2 x base(n) x 1e5 FLIP");
            }
            // base(n)/2 = (21 - n)/16: day schedule against day 1, exact.
            assertEq(_refFlipRaw(10_000, 40_000, n, 21_600, 0) * 20, _refFlipRaw(10_000, 40_000, 1, 21_600, 0) * (21 - n), "(21-n)/16");
        }
        // Day 7's base is 70% of day 1's; day 2's opening stays below day 1's close.
        assertEq(_baseMilli(7) * 100, _baseMilli(1) * 70, "day 7 = 70% of day 1");
        assertLt(_baseMilli(2) * _bonusPpm(0), _baseMilli(1) * _bonusPpm(21_600), "tomorrow's open < today's close");
    }

    /// @notice r = K/(K + V): 1 for the first ETH, 1/2 at 46 ETH, 1/3 at 92 ETH; the cohort's
    ///         expected FLIP value base x r x V stays below base x K.
    function test_VolumeFactorShape() public pure {
        assertApproxEqAbs(_refFlipRaw(10_000, 40_000, 1, 21_600, 460_000) * 2, _refFlipRaw(10_000, 40_000, 1, 21_600, 0), 2, "r = 1/2 at 46 ETH");
        assertApproxEqAbs(_refFlipRaw(10_000, 40_000, 1, 21_600, 920_000) * 3, _refFlipRaw(10_000, 40_000, 1, 21_600, 0), 3, "r = 1/3 at 92 ETH");
        uint256 prev;
        for (uint256 v = 100; v < 1e12; v *= 7) {
            uint256 total = _refFlipRaw(v, 40_000, 1, 21_600, v); // whole cohort at nominal mean
            uint256 cap = _refFlipRaw(460_000, 40_000, 1, 21_600, 0); // base x K
            assertLt(total, cap, "cohort FLIP below base x K");
            assertGe(total, prev, "monotone in V");
            prev = total;
        }
    }

    /// @notice Check 7: the nominal-mean FLIP value over the sale stays below
    ///         K_day x sum(base) x 1.05 (about 718 ETH, 72M FLIP), for any daily volumes up to
    ///         9M ETH a day. (The ladder's exact mean is 40,000.2 bps, 5 ppm above the nominal
    ///         40,000, so the bound is approached only beyond ~9.2M ETH in a single day.)
    function testFuzz_NominalMeanTotalBelowCeiling(uint64[7] memory vRaw) public pure {
        uint256 total; // tenths of a FLIP
        for (uint256 n = 1; n <= 7; ++n) {
            uint256 v = uint256(vRaw[n - 1]) % 90_000_000_000; // units, < 9M ETH
            // Overall mean = 0.5 x conditional ladder mean, all orders at the opening bonus.
            total += _refFlipRaw(v, LADDER_MEAN_DECI_BPS, n, 0, v) / 2;
        }
        uint256 sumBaseMilli;
        for (uint256 n = 1; n <= 7; ++n) sumBaseMilli += _baseMilli(n);
        assertEq(sumBaseMilli, 14_875, "sum of base means = 14.875");
        // 46 ETH x 14.875 x 1.05 in FLIP (1e5 FLIP per ETH), x10 for the deci-bps scale.
        uint256 ceiling = 46 * sumBaseMilli * 105 * 1e5 * 10 / (1000 * 100);
        assertEq(ceiling / 10, 71_846_250, "ceiling = 71.85M FLIP");
        assertLt(ceiling / 10, 72_000_000, "below 72M FLIP");
        assertLe(total, ceiling, "nominal-mean total below the ceiling");
    }

    /// @dev Drive one cohort whose orders all keep FLIP coin credit; returns the resolutions.
    function _driveFlipCohort(uint256 c, uint32[] memory ids) internal returns (Res[] memory got, uint256 word) {
        uint256 n = ids.length;
        for (uint256 i;; ++i) {
            word = uint256(keccak256(abi.encode("fs-all-flip", c, i)));
            bool ok = true;
            for (uint256 j; j < n && ok; ++j) {
                ok = _refCategory(word, c, j, ids[j]) == 0 && _passBit(word, c, j, ids[j]) == 0;
            }
            if (ok) break;
        }
        uint256 q = _refQ(c, _degPool());
        _warpTo(_dayOf(c) + 1, 0);
        vm.recordLogs();
        _drive(word);
        got = _resolved(vm.getRecordedLogs());
        Res[] memory want = _refCohort(c, word, q);
        assertEq(got.length, n, "cohort size");
        for (uint256 j; j < n; ++j) _assertRes(got[j], want[j], "flip order vs reference");
    }

    function _secsOf(Vm.Log[] memory logs) internal view returns (uint256[] memory secs) {
        uint256 n = _countSig(logs, SIG_BUY);
        secs = new uint256[](n);
        uint256 k;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length > 0 && logs[i].topics[0] == SIG_BUY) {
                (,,, secs[k++]) = abi.decode(logs[i].data, (uint8, uint32, uint256, uint256));
            }
        }
    }

    /// @notice Driven, check 7: orders at opening, 3h, 6h and 9h carry the capped bonus input,
    ///         and their FLIP matches spec §5 within the 100-FLIP collapse, at the cohort's V.
    function test_DrivenFlipAtOpeningThreeSixLater() public {
        uint256[4] memory at = [uint256(0), 3 hours, 6 hours, 9 hours];
        address[4] memory who = [a, b, c3, d4];
        uint32[] memory ids = new uint32[](4);
        _warpTo(3, 0);
        _drive(0); // accept cohort 2 before its first order
        vm.recordLogs();
        for (uint256 j; j < 4; ++j) {
            vm.warp(_dayStart(3) + at[j]);
            _buy(who[j], 0.5 ether);
            ids[j] = game.walletIdOf_g3120(who[j]);
        }
        uint256[] memory secs = _secsOf(vm.getRecordedLogs());
        assertEq(secs[0], 0, "opening s = 0");
        assertEq(secs[1], 10_800, "3h");
        assertEq(secs[2], 21_600, "6h");
        assertEq(secs[3], 21_600, "later capped at 21,600");
        uint256 v = _volumeUnits(2) * UNIT;
        (Res[] memory got, uint256 word) = _driveFlipCohort(2, ids);
        for (uint256 j; j < 4; ++j) {
            uint256 bps = _ladderBps(uint256(keccak256(abi.encode(uint256(56), _seed(word, 2, j, ids[j])))));
            uint256 spec = _specFlip(0.5 ether, bps, 2, secs[j], v);
            assertApproxEqAbs(got[j].flip, spec, 101, "FLIP = spec within the collapse");
            assertEq(got[j].flip % 100, 0, "collapsed to whole hundreds");
        }
        // Same ladder roll: opening pays 1.05 / 1.025 / 1.0 of the 6h amount.
        uint256 b0 = _refFlipRaw(5000, 40_000, 2, 0, _volumeUnits(2));
        uint256 b6 = _refFlipRaw(5000, 40_000, 2, 21_600, _volumeUnits(2));
        assertApproxEqAbs(b0 * 100, b6 * 105, 105, "+5% at opening");
    }

    /// @notice Driven, check 7: the day factor (21 - n)/16 across day boundaries, at the same
    ///         bonus and V; an order at a day's first second takes the full bonus in the new
    ///         cohort, the second before belongs to the previous cohort with no bonus.
    function test_DrivenDayScheduleAndBoundaries() public {
        uint32 ida = game.walletIdOf_g3120(a);
        uint32[] memory one = new uint32[](1);
        one[0] = ida;
        // Last second of index 2 (cohort 1, s capped) and first second of index 3 (cohort 2, s = 0).
        vm.warp(_dayStart(3) - 1);
        _buy(a, 1 ether);
        assertEq(_count(1), 1, "last second of the day is cohort 1");
        (Res[] memory r1, uint256 w1) = _driveFlipCohort(1, one);
        _buy(a, 1 ether);
        assertEq(_count(2), 1, "accepted request opens cohort 2");
        (Res[] memory r2, uint256 w2) = _driveFlipCohort(2, one);
        uint256 bps1 = _ladderBps(uint256(keccak256(abi.encode(uint256(56), _seed(w1, 1, 0, ida)))));
        uint256 bps2 = _ladderBps(uint256(keccak256(abi.encode(uint256(56), _seed(w2, 2, 0, ida)))));
        assertApproxEqAbs(r1[0].flip, _specFlip(1 ether, bps1, 1, 86_399, 1 ether), 101, "day 1, no bonus");
        assertApproxEqAbs(r2[0].flip, _specFlip(1 ether, bps2, 2, 0, 1 ether), 101, "day 2, full bonus");

        // Day 7 at s >= 6h against day 1's formula: (21 - 7)/(21 - 1) = 0.7.
        for (uint256 c = 3; c <= 7; ++c) {
            _warpTo(_dayOf(c), 7 hours);
            if (c == 7) {
                _buy(a, 1 ether);
                (Res[] memory r7, uint256 w7) = _driveFlipCohort(7, one);
                uint256 bps7 = _ladderBps(uint256(keccak256(abi.encode(uint256(56), _seed(w7, 7, 0, ida)))));
                assertApproxEqAbs(r7[0].flip, _specFlip(1 ether, bps7, 7, 21_600, 1 ether), 101, "day 7 schedule");
                assertApproxEqAbs(_refFlipRaw(10_000, bps7, 7, 21_600, 10_000) * 20, _refFlipRaw(10_000, bps7, 1, 21_600, 10_000) * 14, 20, "0.7x of day 1");
            } else {
                _driveDay(_dayOf(c) + 1, 0);
            }
        }
    }

    /// @notice Driven, check 7: across cohort volumes 0.01, 46, 92 and 460 ETH the single
    ///         order's FLIP scales by K/(K + V).
    function test_DrivenVolumeFactorAcrossVolumes() public {
        uint256[4] memory vols = [uint256(0.01 ether), 46 ether, 92 ether, 460 ether];
        _earnCredit(a, 400 ether);
        uint32 ida = game.walletIdOf_g3120(a);
        uint32[] memory one = new uint32[](1);
        one[0] = ida;
        for (uint256 k; k < 4; ++k) {
            uint256 c = k + 1;
            _warpTo(_dayOf(c), 7 hours);
            _buy(a, vols[k]);
            (Res[] memory r, uint256 w) = _driveFlipCohort(c, one);
            uint256 bps = _ladderBps(uint256(keccak256(abi.encode(uint256(56), _seed(w, c, 0, ida)))));
            uint256 spec = _specFlip(vols[k], bps, c, 21_600, vols[k]);
            uint256 tol = 101 + spec / 1e12; // WAD-route rounding on the largest orders
            assertApproxEqAbs(r[0].flip, spec, tol, "FLIP x K/(K+V)");
        }
    }

    /// @notice Check 7 / §5: a FLIP result below one whole FLIP pays the WWXRP consolation.
    ///         A 2,000,000 ETH cohort (credit written via vm.store: a real 8M ETH qualifying
    ///         spend is impractical) leaves a 0.01 ETH FLIP roll below 1 FLIP.
    function test_BelowOneFlipPaysWwxrp() public {
        _seedCredit(a, 2_000_000 ether);
        vm.deal(a, 2_000_001 ether);
        _buy(a, 2_000_000 ether);
        _buy(b, 0.01 ether);
        uint32 idb = game.walletIdOf_g3120(b);
        uint256 word = _searchCategory(1, 1, idb, 0, 0);
        uint256 q = _refQ(1, _degPool());
        assertEq(_refFlipRaw(100, 143_204, 1, 21_600, _volumeUnits(1)), 0, "even the top ladder roll is < 1 FLIP");
        _warpTo(3, 1 hours);
        vm.recordLogs();
        _drive(word);
        Res[] memory got = _resolved(vm.getRecordedLogs());
        Res[] memory want = _refCohort(1, word, q);
        _assertRes(got[1], want[1], "small order");
        assertEq(got[1].flip, 0, "no FLIP");
        assertEq(got[1].normalPasses + got[1].highPasses, 0, "no passes");
        assertEq(got[1].wwxrp, 1, "WWXRP consolation");
        assertEq(got[1].dgnrs, 0, "no sDGNRS");
    }

    /// @notice Spec §5: a minimum (0.01 ETH) day-7 box at the bottom ladder roll and no bonus
    ///         reaches the sub-1-FLIP WWXRP case only on a day selling about 57,000 ETH.
    function test_MinimumBoxWwxrpThresholdNear57kEth() public pure {
        uint256 lowest = LOW_BASE; // roll 0
        assertGe(_refFlipRaw(100, lowest, 7, 21_600, 560_000_000), 1, "56,000 ETH day: still >= 1 FLIP");
        assertEq(_refFlipRaw(100, lowest, 7, 21_600, 570_000_000), 0, "57,000 ETH day: below 1 FLIP");
    }

    /// @notice The 100-FLIP collapse is EV-preserving: over the 100 rounding draws the mean of
    ///         the collapsed amount equals the raw amount.
    function test_CollapseIsEvPreserving() public pure {
        uint256 raw = 12_345;
        uint256 sum;
        for (uint256 e; e < 100; ++e) sum += FlipRoundLib.roundFlipToHundreds(raw, e);
        assertEq(sum, raw * 100, "E[collapse] = raw");
    }
}
