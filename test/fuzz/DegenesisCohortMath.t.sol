// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DegenesisHarness} from "./helpers/DegenesisHarness.sol";

/// @title DegenesisCohortMath -- Q, L and the sDGNRS formula (spec §4; §10 checks 3, 5)
/// @notice Q = min(floor(2.5T), floor(R * 2 / 3)) with T = 20B tokens (raw 1e12 per token in the
///         module's units) on days 1-3 and 10B on days 4-7; L = floor(1.5Q) bounds every cohort's
///         payout; an sDGNRS award is floor(x * Q * m / (V * 10_000)), m uniform on [5000, 15000],
///         with V the whole cohort volume (no normalization by winners).
contract DegenesisCohortMath is DegenesisHarness {
    address internal a;
    address internal b;
    address internal c3;

    function setUp() public override {
        super.setUp();
        a = _player("cm-a");
        b = _player("cm-b");
        c3 = _player("cm-c");
        _drive(0);
        _earnCredit(a, 30 ether);
        _earnCredit(b, 30 ether);
        _earnCredit(c3, 30 ether);
        _driveDay(2, 0);
    }

    struct Priced {
        uint256 c;
        uint256 volume;
        uint256 q;
        uint24 bound;
    }

    function _pricedOf(Vm.Log[] memory logs) internal view returns (Priced memory p) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length > 1 && logs[i].topics[0] == SIG_PRICED) {
                p.c = uint256(logs[i].topics[1]);
                (p.volume, p.q, p.bound) = abi.decode(logs[i].data, (uint256, uint256, uint24));
            }
        }
    }

    function _closedPaid(Vm.Log[] memory logs, uint256 c) internal view returns (uint256 paid, bool found) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length > 1 && logs[i].topics[0] == SIG_CLOSED
                && uint256(logs[i].topics[1]) == c) {
                paid = abi.decode(logs[i].data, (uint256));
                found = true;
            }
        }
    }

    /// @notice Initial Degenesis inventory is the 10% allocation, and cohort 1 prices at
    ///         Q = 2.5T = 50B tokens (the 2/3 R cap is 66.7B), L = 75B.
    function test_CohortOnePricesAtTwoAndHalfTarget() public {
        uint256 r = _degPool();
        assertEq(r, 100_000_000_000 * 1e12, "Degenesis inventory = 100B tokens");
        _buy(a, 0.5 ether);
        _warpTo(3, 1 hours);
        _requestOnly(uint256(keccak256("cm-q1")));
        assertEq(_activeQ(), T_EARLY * 5 / 2, "Q = 2.5T");
        assertEq(_activeQ(), 50_000_000_000 * 1e12, "Q = 50B tokens");
        assertLt(_activeQ(), r * 2 / 3, "inventory cap not binding");
        assertEq(_activeQ() * 3 / 2, 75_000_000_000 * 1e12, "L = 75B tokens");
        assertEq(_activeDay(), 3, "bound to day 3");
        assertEq(_activePaid(), 0, "nothing paid at pricing");
        assertEq(_activeCursor(), 0, "cursor at 0");
    }

    /// @notice Across a whole sale every cohort prices at min(2.5T, 2/3 R) from the inventory
    ///         left after the previous cohort settled, T switching to 10B from day 4; each pays
    ///         at most L = 1.5Q; every order matches the reference.
    function test_QAcrossSaleUsesTargetAndInventory() public {
        for (uint256 c = 1; c <= 7; ++c) this.checkCohortPricing(c);
        assertEq(_closed(), 7, "sale closed");
        assertEq(_degPool(), 0, "inventory burned");
    }

    /// @dev Keep the independent per-order reference in its own frame so the
    /// via-IR optimizer does not inline it into the seven-cohort driver loop.
    function checkCohortPricing(uint256 c) external {
        require(msg.sender == address(this), "cohort assertion self-call");
        uint24 d = _dayOf(c);
        if (c > 1) _warpTo(d, 2 hours);
        _buy(a, 0.37 ether + c * 0.0001 ether);
        _buy(b, 1.2 ether);
        _buy(c3, 0.01 ether * c);
        _buy(a, 2 ether);
        uint256 r = _degPool();
        uint256 word = uint256(keccak256(abi.encode("cm-sale", c)));
        uint256 expQ = _refQ(c, r);
        assertEq(expQ, c <= 3 ? _min(T_EARLY * 5 / 2, r * 2 / 3) : _min(T_LATE * 5 / 2, r * 2 / 3), "ref Q");
        _warpTo(d + 1, 1 hours);
        vm.recordLogs();
        _drive(word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Priced memory p = _pricedOf(logs);
        assertEq(p.c, c, "cohort priced");
        assertEq(p.q, expQ, "Q");
        assertEq(p.volume, _volumeUnits(c) * UNIT, "V");
        assertEq(p.bound, d + 1, "bound day");
        Res[] memory got = _resolved(logs);
        Res[] memory want = _refCohort(c, word, expQ);
        uint256 sum;
        for (uint256 i; i < got.length; ++i) {
            _assertRes(got[i], want[i], "sale order");
            sum += got[i].dgnrs;
        }
        (uint256 paid, bool found) = _closedPaid(logs, c);
        assertTrue(found, "closed");
        assertEq(paid, sum, "paid total = sum of awards");
        assertLe(paid, expQ * 3 / 2, "paid <= L");
        if (c < 7) assertEq(r - _degPool(), paid, "inventory fell by paid");
    }

    /// @notice Check 3: a single order holding the whole volume and rolling the maximum
    ///         multiplier pays exactly L = 1.5Q, never more; the next cohort is then priced on
    ///         the 2/3 R inventory cap.
    function test_MaxWinPaysExactlyLAndCapBindsNext() public {
        _buy(a, 3 ether);
        uint32 id = game.walletIdOf_g3120(a);
        uint256 word = _searchCategory(1, 0, id, 1, 15_000);
        assertEq(_refMultBps(word, 1, 0, id), 15_000, "max multiplier");
        uint256 q = _refQ(1, _degPool());
        _warpTo(3, 1 hours);
        vm.recordLogs();
        _drive(word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Res[] memory got = _resolved(logs);
        assertEq(got.length, 1, "one order");
        assertEq(got[0].dgnrs, q * 3 / 2, "max award = L");
        (uint256 paid,) = _closedPaid(logs, 1);
        assertEq(paid, q * 3 / 2, "cohort paid = L");
        uint256 r2 = _degPool();
        assertEq(r2, 100_000_000_000 * 1e12 - q * 3 / 2, "inventory = R - L");

        _buy(b, 0.2 ether);
        _warpTo(4, 1 hours);
        _requestOnly(uint256(keccak256("cm-next")));
        assertEq(_activeQ(), r2 * 2 / 3, "cap binds: Q = floor(2/3 R)");
        assertLt(_activeQ(), T_EARLY * 5 / 2, "below 2.5T");
    }

    /// @notice Check 3 (fuzz): with every order of a cohort forced to the maximum sDGNRS
    ///         multiplier, the summed awards never exceed L = floor(1.5Q) <= R.
    function testFuzz_AllOrdersMaxNeverExceedL(uint256 seed, uint8 nRaw, uint80 qRaw, uint256 rRaw) public pure {
        uint256 n = 1 + uint256(nRaw) % 64;
        uint256 r = 1 + rRaw % (100_000_000_000 * 1e12);
        uint256 q = _min(uint256(qRaw), _refQ(1 + seed % 7, r));
        uint256[] memory u = new uint256[](n);
        uint256 v;
        for (uint256 i; i < n; ++i) {
            u[i] = 100 + uint256(keccak256(abi.encode(seed, i))) % (uint256(1) << (8 + i % 30));
            v += u[i];
        }
        uint256 sum;
        for (uint256 i; i < n; ++i) sum += (u[i] * q * 15_000) / (v * 10_000);
        assertLe(sum, q * 3 / 2, "sum of max awards <= L");
        assertLe(q * 3 / 2, r, "L <= R");
    }

    /// @notice Check 3 (fuzz over words): the reference awards of an arbitrary cohort never
    ///         exceed L, whatever the categories and multipliers.
    function testFuzz_AnyWordPaysWithinL(uint256 word, uint256 seed, uint8 nRaw) public pure {
        uint256 n = 1 + uint256(nRaw) % 40;
        uint256 q = T_EARLY * 5 / 2;
        uint256[] memory u = new uint256[](n);
        uint256 v;
        for (uint256 i; i < n; ++i) {
            u[i] = 100 + uint256(keccak256(abi.encode(seed, i))) % 1_000_000;
            v += u[i];
        }
        uint256 sum;
        for (uint256 i; i < n; ++i) sum += _refOutcome(word, 1, i, uint32(3 + i), u[i], 0, v, q).dgnrs;
        assertLe(sum, q * 3 / 2, "awards <= L");
    }

    /// @notice Check 5: a 9 ETH / 1 ETH split of one cohort has a 9:1 expected sDGNRS ratio
    ///         before rounding (expectation over the 10,001 multipliers and the 40% category),
    ///         from the formula alone, with V the whole cohort volume.
    function test_NineToOneExpectedRatio() public pure {
        uint256 q = T_EARLY * 5 / 2;
        uint256 v = 100_000; // 10 ETH in units
        uint256 ua = 90_000;
        uint256 ub = 10_000;
        // Exact expectation before rounding: E = 0.4 * x * Q * mean(m) / (V * 10_000), mean(m) = 10_000.
        uint256 sumM;
        for (uint256 m = 5000; m <= 15_000; ++m) sumM += m;
        assertEq(sumM, 10_000 * 10_001, "mean multiplier = 1.0x");
        // E_A / E_B = (ua * Q * sumM) / (ub * Q * sumM) = 9 exactly (no floor taken).
        assertEq(ua * q * sumM, 9 * (ub * q * sumM), "9:1 before rounding");
        // With per-award floors the realised expectation stays 9:1 within one raw unit per term.
        uint256 ea;
        uint256 eb;
        for (uint256 m = 5000; m <= 15_000; m += 1) {
            ea += (ua * q * m) / (v * 10_000);
            eb += (ub * q * m) / (v * 10_000);
        }
        assertApproxEqAbs(ea, 9 * eb, 9 * 10_001, "floors move the ratio by at most rounding");
        // Expected tokens per ETH are equal for both buyers: 40% * Q / V.
        assertEq(ea / 9, eb, "equal per-ETH expectation");
    }

    /// @notice Check 5 (driven): the 9 ETH order's award uses the whole cohort volume V as its
    ///         denominator, whether or not the 1 ETH order also won sDGNRS. There is no
    ///         normalization by winners.
    function test_NineToOneNoNormalizationByWinners() public {
        _buy(a, 9 ether);
        _buy(b, 1 ether);
        uint32 ida = game.walletIdOf_g3120(a);
        uint32 idb = game.walletIdOf_g3120(b);
        uint256 q = _refQ(1, _degPool());
        uint256 snap = vm.snapshotState();

        // Word 1: A wins sDGNRS, B does not.
        uint256 w1;
        for (uint256 i;; ++i) {
            w1 = uint256(keccak256(abi.encode("ninetoone-solo", i)));
            if (_refCategory(w1, 1, 0, ida) == 1 && _refCategory(w1, 1, 1, idb) != 1) break;
        }
        _warpTo(3, 1 hours);
        vm.recordLogs();
        _drive(w1);
        Res[] memory got = _resolved(vm.getRecordedLogs());
        uint256 ma = _refMultBps(w1, 1, 0, ida);
        assertEq(got[0].dgnrs, (90_000 * q * ma) / (100_000 * 10_000), "A: x * Q * m / (V * 10_000)");
        assertLt(got[0].dgnrs, (q * ma) / 10_000, "A is not normalized to the winners' volume");
        assertEq(got[1].dgnrs, 0, "B no sDGNRS");

        // Word 2: both win sDGNRS; each award uses only its own amount and multiplier.
        vm.revertToState(snap);
        uint256 w2;
        for (uint256 i;; ++i) {
            w2 = uint256(keccak256(abi.encode("ninetoone-both", i)));
            if (_refCategory(w2, 1, 0, ida) == 1 && _refCategory(w2, 1, 1, idb) == 1) break;
        }
        _warpTo(3, 1 hours);
        vm.recordLogs();
        _drive(w2);
        got = _resolved(vm.getRecordedLogs());
        uint256 ma2 = _refMultBps(w2, 1, 0, ida);
        uint256 mb2 = _refMultBps(w2, 1, 1, idb);
        assertEq(got[0].dgnrs, (90_000 * q * ma2) / (100_000 * 10_000), "A award");
        assertEq(got[1].dgnrs, (10_000 * q * mb2) / (100_000 * 10_000), "B award");
        // Same multiplier would give exactly 9:1 up to one floor.
        assertApproxEqAbs((90_000 * q * mb2) / (100_000 * 10_000), 9 * got[1].dgnrs, 9, "9:1 at equal multiplier");
    }

    function _min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }
}
