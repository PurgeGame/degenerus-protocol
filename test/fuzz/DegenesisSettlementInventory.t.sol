// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DegenesisHarness} from "./helpers/DegenesisHarness.sol";

/// @title DegenesisSettlementInventory -- zero inventory and dust (spec §4, check 6)
/// @notice An sDGNRS result pays the WWXRP consolation when the cohort has no inventory to pay
///         from (Q = 0, or the pool empty at payment), and when the raw-unit award rounds to
///         zero. A short pool clamps the payment to what is left. Real play cannot empty the
///         pool (L = 1.5Q <= R), so these cases write the sDGNRS Degenesis pool balance with
///         vm.store (`_setDegPool`, which keeps sDGNRS's own token balance consistent).
contract DegenesisSettlementInventory is DegenesisHarness {
    address internal a;
    address internal b;

    function setUp() public override {
        super.setUp();
        a = _player("inv-a");
        b = _player("inv-b");
        _drive(0);
        _earnCredit(a, 5 ether);
        _earnCredit(b, 5 ether);
        _driveDay(2, 0);
    }

    function _closedPaid(Vm.Log[] memory logs) internal view returns (uint256 paid) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length > 0 && logs[i].topics[0] == SIG_CLOSED) {
                paid = abi.decode(logs[i].data, (uint256));
            }
        }
    }

    /// @notice Empty pool at pricing: Q = 0, the cohort still prices and settles, an sDGNRS
    ///         result pays WWXRP, no sDGNRS moves.
    function test_EmptyPoolAtPricingPaysWwxrp() public {
        _buy(a, 1 ether);
        uint32 id = game.walletIdOf(a);
        uint256 word = _searchCategory(1, 0, id, 1, 0);
        _setDegPool(0);
        _warpTo(3, 1 hours);
        vm.recordLogs();
        _drive(word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Res[] memory got = _resolved(logs);
        assertEq(got.length, 1, "resolved");
        assertEq(got[0].dgnrs, 0, "no sDGNRS");
        assertEq(got[0].wwxrp, 1, "WWXRP consolation");
        assertEq(got[0].flip, 0, "no FLIP");
        assertEq(_closedPaid(logs), 0, "nothing paid");
        assertEq(_closed(), 1, "closed");
        _assertRes(got[0], _refOutcome(word, 1, 0, id, 10_000, 3600, 10_000, 0), "Q = 0 reference");
    }

    /// @notice Pool emptied after pricing: the award is nonzero, the clamping transfer pays 0,
    ///         and the order pays WWXRP instead.
    function test_PoolEmptyAtPaymentPaysWwxrp() public {
        _buy(a, 1 ether);
        uint32 id = game.walletIdOf(a);
        uint256 word = _searchCategory(1, 0, id, 1, 0);
        _warpTo(3, 1 hours);
        _requestOnly(word);
        assertGt(_activeQ(), 0, "priced with inventory");
        _setDegPool(0);
        vm.recordLogs();
        _drive(word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Res[] memory got = _resolved(logs);
        assertEq(got[0].dgnrs, 0, "nothing paid");
        assertEq(got[0].wwxrp, 1, "WWXRP instead");
        assertEq(_closedPaid(logs), 0, "cohort paid 0");
    }

    /// @notice A short pool clamps the first sDGNRS payment to what is left; later sDGNRS
    ///         results find it empty and pay WWXRP; the cohort's paid total equals the pool.
    function test_ShortPoolClampsThenConsoles() public {
        _buy(a, 1 ether);
        _buy(b, 1 ether);
        uint32 ida = game.walletIdOf(a);
        uint32 idb = game.walletIdOf(b);
        uint256 word;
        for (uint256 i;; ++i) {
            word = uint256(keccak256(abi.encode("inv-short", i)));
            if (_refCategory(word, 1, 0, ida) == 1 && _refCategory(word, 1, 1, idb) == 1) break;
        }
        _warpTo(3, 1 hours);
        _requestOnly(word);
        uint256 left = 12_345;
        _setDegPool(left);
        address payee = a;
        uint256 bal0 = sdgnrs.balanceOf(payee);
        vm.recordLogs();
        _drive(word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Res[] memory got = _resolved(logs);
        assertEq(got[0].dgnrs, left, "first payment clamped to the pool");
        assertEq(got[0].wwxrp, 0, "a partial payment is not a consolation");
        assertEq(got[1].dgnrs, 0, "second finds the pool empty");
        assertEq(got[1].wwxrp, 1, "and pays WWXRP");
        assertEq(_closedPaid(logs), left, "paid = what the pool held");
        assertEq(sdgnrs.balanceOf(payee) - bal0, left, "payee received the clamped amount");
    }

    /// @notice Dust: with a tiny inventory (Q = 2 raw units) a small order's raw-unit award
    ///         floors to zero and pays WWXRP; the large order still gets its formula award.
    function test_DustAwardPaysWwxrp() public {
        _buy(a, 1 ether);
        _buy(b, 0.01 ether);
        uint32 ida = game.walletIdOf(a);
        uint32 idb = game.walletIdOf(b);
        uint256 word;
        for (uint256 i;; ++i) {
            word = uint256(keccak256(abi.encode("inv-dust", i)));
            if (_refCategory(word, 1, 0, ida) == 1 && _refCategory(word, 1, 1, idb) == 1) break;
        }
        _setDegPool(3);
        _warpTo(3, 1 hours);
        vm.recordLogs();
        _drive(word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Res[] memory got = _resolved(logs);
        uint256 q = 2; // floor(3 * 2 / 3)
        uint256 v = 10_100;
        uint256 ma = _refMultBps(word, 1, 0, ida);
        assertEq(got[0].dgnrs, (10_000 * q * ma) / (v * 10_000), "large order formula award");
        assertGt(got[0].dgnrs, 0, "large order nonzero");
        assertEq((100 * q * _refMultBps(word, 1, 1, idb)) / (v * 10_000), 0, "small award rounds to 0");
        assertEq(got[1].dgnrs, 0, "dust pays no sDGNRS");
        assertEq(got[1].wwxrp, 1, "dust pays WWXRP");
        _assertRes(got[1], _refOutcome(word, 1, 1, idb, 100, 3600, v, q), "dust reference");
    }
}
