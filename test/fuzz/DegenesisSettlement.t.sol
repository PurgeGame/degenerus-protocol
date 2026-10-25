// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DegenesisHarness} from "./helpers/DegenesisHarness.sol";

/// @title DegenesisSettlement -- per-order resolution against the reference, partition and
///         reorder invariance (spec §10 checks 1, 4, 7)
/// @notice Every DegenesisOrderResolved is compared field for field with `_refOutcome`, computed
///         from the stored lanes, the cohort's frozen V and Q and the VRF word that answered the
///         bound day's request. Settling the same cohort on different gas budgets, or with other
///         activity and callers interleaved between chunks, yields identical per-order rewards.
contract DegenesisSettlement is DegenesisHarness {
    address[5] internal buyers;

    function setUp() public override {
        super.setUp();
        _drive(0);
        for (uint256 i; i < 5; ++i) {
            buyers[i] = _player(string.concat("st-", vm.toString(i)));
            _earnCredit(buyers[i], 50 ether);
        }
        _driveDay(2, 0);
    }

    /// @dev `n` orders on the current day from the five buyers, amounts on the 0.0001 grid,
    ///      spread over the day so the early bonus input varies.
    ///      Times are absolute from 2h into day index 2 (via-IR may re-read block.timestamp).
    function _placeOrders(uint256 n, uint256 stepSecs) internal {
        for (uint256 i; i < n; ++i) {
            vm.warp(_dayStart(2) + 2 hours + i * stepSecs);
            _buy(buyers[i % 5], 0.01 ether + (i % 7) * 0.0013 ether + (i % 3) * 0.25 ether);
        }
    }

    function _assertMatchesReference(Res[] memory got, uint256 c, uint256 word, uint256 q) internal view {
        Res[] memory want = _refCohort(c, word, q);
        assertEq(got.length, want.length, "resolved count");
        for (uint256 i; i < got.length; ++i) _assertRes(got[i], want[i], string.concat("order ", vm.toString(i)));
    }

    function _assertSame(Res[] memory x, Res[] memory y) internal pure {
        assertEq(x.length, y.length, "same count");
        for (uint256 i; i < x.length; ++i) _assertRes(x[i], y[i], string.concat("partition order ", vm.toString(i)));
    }

    /// @notice Check 1: exclusive categories, independent size rolls, WWXRP consolation; every
    ///         order resolves exactly as the reference model of spec §3-§5 says, and the sDGNRS
    ///         paid equals the cohort's paid total.
    function test_EveryOrderMatchesReference() public {
        _placeOrders(60, 5 minutes);
        uint256 word = uint256(keccak256("settlement-reference"));
        uint256 q = _refQ(1, _degPool());
        uint256 pool0 = _degPool();
        _warpTo(3, 1 hours);
        vm.recordLogs();
        _drive(word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Res[] memory got = _resolved(logs);
        _assertMatchesReference(got, 1, word, q);

        uint256 paid;
        uint256[3] memory cats;
        for (uint256 i; i < got.length; ++i) {
            paid += got[i].dgnrs;
            bool f = got[i].flip != 0 || got[i].normalPasses != 0 || got[i].highPasses != 0;
            bool s = got[i].dgnrs != 0;
            assertTrue(!(f && s), "never both FLIP and sDGNRS");
            if (s) assertEq(got[i].wwxrp, 0, "sDGNRS win carries no consolation");
            cats[_refCategory(word, 1, i, got[i].id)]++;
        }
        assertGt(cats[0], 0, "some FLIP results");
        assertGt(cats[1], 0, "some sDGNRS results");
        assertEq(pool0 - _degPool(), paid, "pool fell by exactly the sDGNRS paid");
        assertLe(paid, q * 3 / 2, "paid within L");
        assertEq(_closed(), 1, "cohort closed");
    }

    /// @notice Check 4: settling one cohort on different gas budgets (different chunkings)
    ///         gives identical per-order rewards, across the 128-order chunk boundary.
    function test_PartitionInvariance() public {
        _placeOrders(150, 2 minutes);
        uint256 word = uint256(keccak256("settlement-partition"));
        uint256 q = _refQ(1, _degPool());
        _warpTo(3, 1 hours);
        _requestOnly(word);
        uint256 snap = vm.snapshotState();

        vm.recordLogs();
        _drive(word);
        Res[] memory full = _resolved(vm.getRecordedLogs());
        assertEq(_closed(), 1, "full-gas run closed");

        vm.revertToState(snap);
        uint256[4] memory budgets = [uint256(1_300_000), 1_700_000, 1_100_000, 2_200_000];
        vm.recordLogs();
        uint256 calls;
        for (uint256 i; i < 2000 && _closed() == 0; ++i) {
            if (!_mineStep(budgets[i % 4])) break;
            ++calls;
        }
        _drive(word);
        Res[] memory chunked = _resolved(vm.getRecordedLogs());
        assertEq(_closed(), 1, "chunked run closed");
        assertGt(calls, 4, "settlement spread over more calls than the two full-gas chunks");

        assertEq(full.length, 150, "every order resolved once");
        _assertSame(full, chunked);
        _assertMatchesReference(full, 1, word, q);
    }

    /// @notice Check 4: other purchases, next-cohort orders and different callers between
    ///         settlement chunks do not change any order's reward.
    function test_InterleavedActivityDoesNotChangeRewards() public {
        _placeOrders(40, 7 minutes);
        uint256 word = uint256(keccak256("settlement-interleave"));
        _warpTo(3, 1 hours);
        _requestOnly(word);
        uint256 snap = vm.snapshotState();

        vm.recordLogs();
        _drive(word);
        Res[] memory plain = _resolved(vm.getRecordedLogs());

        vm.revertToState(snap);
        vm.recordLogs();
        for (uint256 i; i < 2000 && _closed() == 0; ++i) {
            if (i % 3 == 0) _buy(buyers[i % 5], 0.0101 ether); // cohort 2 order
            if (i % 5 == 1) _earnCredit(buyers[(i + 1) % 5], 0.01 ether); // ordinary lootbox
            address caller = makeAddr(string.concat("miner-", vm.toString(i)));
            _fulfillPending(0);
            vm.prank(caller);
            try game.mineRun{gas: 2_000_000}(0) {} catch {
                vm.prank(caller);
                try game.mineRun(0) {} catch { break; }
            }
        }
        _drive(word);
        Res[] memory mixed = _resolved(vm.getRecordedLogs());
        // Only cohort 1 resolves here (cohort 2 waits for the day-4 request).
        assertEq(plain.length, 40, "plain count");
        _assertSame(plain, mixed);
    }

    /// @notice Check 7: splitting a buy into several orders does not change FLIP scale per ETH,
    ///         and every order uses the cohort's frozen final V, never the running volume.
    function test_SplitBuyKeepsFlipScalePerEth() public {
        address x = buyers[0];
        address whale = buyers[1];
        _warpTo(2, 1 hours);
        uint256 snap = vm.snapshotState();

        // A: one 1 ETH order first, then a 45 ETH order: V = 46 ETH, r = 1/2.
        _buy(x, 1 ether);
        vm.warp(block.timestamp + 1 hours);
        _buy(whale, 45 ether);
        uint32 xid = game.walletIdOf_g3120(x);
        uint256 word = _searchFlipCoin(1, 0, xid);
        uint256 q = _refQ(1, _degPool());
        _warpTo(3, 1 hours);
        vm.recordLogs();
        _drive(word);
        Res[] memory a = _resolved(vm.getRecordedLogs());
        assertGt(a[0].flip, 0, "first order rolled FLIP coin credit");
        uint256 vUnits = 460_000;
        // Frozen V: matches the reference at final V, and is far below a running-V price.
        uint256 frozen = _refOutcome(word, 1, 0, xid, 10_000, 3600, vUnits, q).flip;
        uint256 running = _refOutcome(word, 1, 0, xid, 10_000, 3600, 10_000, q).flip;
        assertEq(a[0].flip, frozen, "priced at frozen V");
        assertGt(running, frozen * 17 / 10, "running-V price would be much larger");

        // B: the same 1 ETH as ten 0.1 ETH orders, same time, same total V.
        vm.revertToState(snap);
        for (uint256 i; i < 10; ++i) _buy(x, 0.1 ether);
        vm.warp(block.timestamp + 1 hours);
        _buy(whale, 45 ether);
        assertEq(_volumeUnits(1), vUnits, "same V");
        uint256 qb = _refQ(1, _degPool());
        assertEq(qb, q, "same Q");
        _warpTo(3, 1 hours);
        vm.recordLogs();
        _drive(word);
        Res[] memory b = _resolved(vm.getRecordedLogs());
        _assertMatchesReference(b, 1, word, q);

        // Expected FLIP per ETH (ladder mean, before the collapse) is identical: one 1 ETH
        // order vs ten 0.1 ETH orders at the same bonus and V.
        uint256 meanBps = 40_000;
        uint256 one = _refFlipRaw(10_000, meanBps, 1, 3600, vUnits);
        uint256 ten = 10 * _refFlipRaw(1000, meanBps, 1, 3600, vUnits);
        assertApproxEqAbs(one, ten, 10, "FLIP scale per ETH unchanged by splitting");
    }
}
