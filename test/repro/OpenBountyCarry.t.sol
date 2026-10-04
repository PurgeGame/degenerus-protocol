// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @title OpenBountyCarry — splitting an AFKing backlog across calls never out-earns one call
/// @notice The knee bounty and its `_openBountyCarry` netting are gone (60d31f775 / 72fc06f6c):
///         mineFlip now pays FLIP on the gas each call measured above its unpaid first
///         MIN_REWARDED_GAS, priced on one clock. The two properties the carry existed for map
///         onto that rule:
///         (1) a backlog drained in several calls pays no more in aggregate than one call
///             draining it (each extra call forfeits another unpaid first million), and
///         (2) a genuinely separate chunk is still paid: every call measuring past the unpaid
///             first million earns a bounty — nothing nets a real chunk down to zero.
///         Organically stamped AFKing boxes from one daily cohort are the backlog.
contract OpenBountyCarry is DeployProtocol {
    uint256 private constant SUBOF_SLOT = 52;
    uint256 private constant SUBSCRIBERS_SLOT = 54;
    uint256 private constant CURSOR_SLOT = 56;
    uint256 private constant PENDING_SHIFT = 224;
    uint256 private _lastFulfilledReqId;

    bytes32 private constant STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(address,uint24,uint256,uint256)");
    bytes32 private constant MINER_WORK_SIG = keccak256("MinerWork(address,uint8,uint256,uint256)");
    /// @dev A realistic per-call allowance for the split leg.
    uint256 private constant SPLIT_ALLOWANCE = 3_000_000;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 10_000_000 ether);
    }

    /// @notice Case 1: one AFKing backlog, drained by one call or split across realistic-allowance
    ///         calls: the split's aggregate bounty never exceeds the single call's.
    function testForcedSplitPaysSingleAggregateBounty() public {
        _setupFundedSubs(100, "bc1_", 20 ether);
        _backlogAtAfking(uint256(keccak256("bc1_w")) | 1);
        uint256 backlog = _pendingCount();
        require(backlog > 40, "fixture: a real AFKing backlog is the next work");
        emit log_named_uint("afking_backlog", backlog);

        uint256 snap = vm.snapshotState();
        (uint256 onePay,) = _mintFlipKeeperCredit(makeAddr("bc1_k1"), 0);
        _drainRest(makeAddr("bc1_k1"));
        uint256 oneCallTotal = onePay + _restPay;
        assertEq(_pendingCount(), 0, "one call drained the backlog");
        vm.revertToState(snap);

        uint256 splitTotal;
        uint256 calls;
        while (_pendingCount() != 0 && calls < 60) {
            (uint256 paid,) = _mintFlipKeeperCredit(makeAddr("bc1_k2"), SPLIT_ALLOWANCE);
            splitTotal += paid;
            ++calls;
        }
        _drainRest(makeAddr("bc1_k2"));
        splitTotal += _restPay;
        emit log_named_uint("one_call_bounty", oneCallTotal);
        emit log_named_uint("split_calls", calls);
        emit log_named_uint("split_aggregate_bounty", splitTotal);

        assertEq(_pendingCount(), 0, "the split calls drained the backlog");
        assertGt(calls, 1, "the realistic allowance really split the backlog");
        assertGt(oneCallTotal, 0, "the single call pays a bounty");
        assertLe(splitTotal, oneCallTotal, "splitting the backlog never out-earns draining it in one call");
    }

    /// @notice Case 2: genuinely separate chunks each pay — every split call that measured past
    ///         the unpaid first million earned a bounty.
    function testTwoRealBatchesEachPayFullBounty() public {
        // 200 subscribers: the backlog left after the lock-releasing call spans several
        // realistic-allowance chunks, more than one of them past the unpaid first million.
        _setupFundedSubs(200, "bc2_", 20 ether);
        _backlogAtAfking(uint256(keccak256("bc2_w")) | 1);
        uint256 pending = _pendingCount();
        require(pending > 40, "fixture: a real AFKing backlog is the next work");

        uint256 paidChunks;
        uint256 calls;
        while (_pendingCount() != 0 && calls < 60) {
            (uint256 paid, uint256 used) = _mintFlipKeeperCredit(makeAddr("bc2_k"), SPLIT_ALLOWANCE);
            if (used > MineFlipGas.MIN_REWARDED_GAS) {
                assertGt(paid, 0, "a chunk past the unpaid first million is paid");
                ++paidChunks;
            } else {
                assertEq(paid, 0, "a chunk inside the unpaid first million is not paid");
            }
            ++calls;
        }
        assertEq(_pendingCount(), 0, "the chunks drained the backlog");
        assertGe(paidChunks, 2, "at least two separate chunks were each paid");
    }

    // ---- helpers ----

    /// @dev One keeper mineFlip (`allowance` 0 = unbounded); returns the FLIP credited to the
    ///      keeper and the execution gas the engine measured.
    function _mintFlipKeeperCredit(address keeper, uint256 allowance) internal returns (uint256 total, uint256 used) {
        vm.recordLogs();
        vm.prank(keeper);
        if (allowance == 0) game.mineFlip();
        else game.mineFlip{gas: allowance}();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].topics.length > 1 &&
                logs[i].topics[0] == STAKE_UPDATED_SIG &&
                address(uint160(uint256(logs[i].topics[1]))) == keeper
            ) {
                (uint256 amount, ) = abi.decode(logs[i].data, (uint256, uint256));
                total += amount;
            }
            if (logs[i].topics.length > 0 && logs[i].topics[0] == MINER_WORK_SIG) {
                (, used,) = abi.decode(logs[i].data, (uint8, uint256, uint256));
            }
        }
    }

    uint256 private _restPay;

    /// @dev Finish the cohort's remaining read consumers with unbounded keeper calls, so both legs
    ///      end in the same engine state; the bounty they earn is accumulated in `_restPay`.
    function _drainRest(address keeper) internal {
        _restPay = 0;
        for (uint256 i; i < 20 && game.advanceDue() && !game.rngComplete(); ++i) {
            (uint256 paid,) = _mintFlipKeeperCredit(keeper, 0);
            _restPay += paid;
        }
    }

    /// @dev Stamp every subscriber for a new day and drive that day's cohort, in minimal
    ///      checkpoints, until its AFKing backlog is the next work. The call that releases the
    ///      day's lock opens what its leftover admits; the rest is the backlog under test. A
    ///      nonzero base fee prices the bounty.
    function _backlogAtAfking(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        _settleIdle(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < 400; ++i) {
            if (game.nextMinerAction() == 9) break; // MinerAction.Afking
            _fulfillPending(vrfWord);
            _stepMinimal();
        }
        assertEq(game.nextMinerAction(), 9, "harness: the AFKing backlog is the next work");
        vm.fee(1 gwei);
    }

    /// @dev Answer outstanding requests and finish delivered cohorts until the engine is idle.
    function _settleIdle(uint256 vrfWord) internal {
        for (uint256 i; i < 20; ++i) {
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (,, bool done) = mockVRF.pendingRequests(reqId);
                if (!done) mockVRF.fulfillRandomWords(reqId, vrfWord + i);
            }
            _finishReadConsumers();
            if (!game.advanceDue() && game.rngComplete()) return;
            if (game.advanceDue()) game.mineFlip();
        }
        revert("harness: cohorts never settled");
    }

    /// @dev One mineFlip given the smallest allowance that succeeds (bisection over snapshots).
    function _stepMinimal() internal {
        uint256 lo = 200_000;
        uint256 hi = 30_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            uint256 snap = vm.snapshotState();
            (bool ok,) = address(game).call{gas: mid}(abi.encodeWithSignature("mineFlip()"));
            vm.revertToStateAndDelete(snap);
            if (ok) hi = mid;
            else lo = mid;
        }
        game.mineFlip{gas: hi}();
    }

    function _pendingCount() internal view returns (uint256) {
        return (uint256(vm.load(address(game), bytes32(CURSOR_SLOT))) >> PENDING_SHIFT) & 0xFFFF;
    }

    function _setupFundedSubs(uint256 n, string memory prefix, uint256 poolEach)
        internal
        returns (address[] memory subs)
    {
        subs = new address[](n);
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            _grantSeat(who); // the AFKing Subscription Token is the subscribe credential (NoCoin without it)
            vm.deal(address(this), poolEach);
            game.depositAfkingFunding{value: poolEach}(who);
            vm.prank(who);
            game.subscribe(address(0), false, false, 1, address(0));
        }
    }

    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < 60; d++) {
            if (!game.advanceDue() && !game.rngLocked() && _wallDaySealed()) break;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked() && _wallDaySealed()) break;
            game.mineFlip();
            _fulfillPending(vrfWord);
        }
    }

    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked() && _wallDaySealed()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked() && _wallDaySealed()) return;
            game.mineFlip();
            _fulfillPending(vrfWord);
        }
    }

    // advanceDue can defer a new day while delivered read consumers remain.
    // Continue through the real advance router until this wall day is sealed.
    function _wallDaySealed() private view returns (bool) {
        return uint24(uint256(vm.load(address(game), bytes32(uint256(0)))) >> 24) == game.currentDayView();
    }

    function _fulfillPending(uint256 vrfWord) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
        }
    }

    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory b;
        while (v > 0) {
            b = abi.encodePacked(uint8(48 + (v % 10)), b);
            v /= 10;
        }
        return string(b);
    }
}
