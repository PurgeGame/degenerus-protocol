// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title PendingBoxCountInvariant — `_pendingBoxCount` never exceeds the stamped boxes ahead of the opener, everywhere
/// @notice The `_pendingBoxCount` counter (compiler-pinned GameSlots) gates
///         mineFlip's AFKing stage. A box is pending while the member sits in the box section, the
///         opener cursor has not passed it and (for a protocol seat) it bought into the cohort, so
///         after EVERY lifecycle transition the count is bounded by that walk. The engine-level exactness
///         (starved call opens exactly one, full drain reaches zero) is asserted in the test body,
///         and settlement is checked independently of the counter and cursor: every box stamped
///         for a cohort must emit its settlement record in exactly one AFKing-stage call.
/// @dev Walks the live box section via vm.load after each step and compares.
///      Covers: subscribe (lootbox + ticket mode), the daily STAGE purchase, partial and full
///      drains (bounded and unbounded mineFlip calls), a cancel rejected WHILE PENDING (box still
///      opened), the cancel after the open (member removed at once), and re-subscribe. Unfunded
///      removal is not driven here: it only reaches members that bought nothing this cohort.
contract PendingBoxCountInvariant is DeployProtocol {
    uint256 private constant SUBSCRIBERS_SLOT = GameSlots.SUBSCRIBERS;
    uint256 private constant CURSOR_SLOT = GameSlots.SUB_CURSOR;
    uint256 private constant PENDING_COUNT_SHIFT = GameSlots.PENDING_BOX_COUNT_OFFSET * 8;
    uint256 private _lastFulfilledReqId;

    uint256 private constant N_LOOTBOX = 12;
    uint256 private constant N_TICKET = 4;

    function setUp() public {
        _deployProtocol();
        // Advance one day off the deploy boundary so the day index is a clean, stable index.
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.deal(address(game), 10_000_000 ether);
        _finishSubscriptionWindow();
    }

    function testPendingBoxCountTracksMarkersAcrossLifecycle() public {
        _assertInvariant("fresh deploy");

        // Subscribes buy nothing at signup, so the counter stays 0.
        address[] memory lootboxSubs = _setupFundedSubs(N_LOOTBOX, "pbl_", 20 ether, false);
        _setupFundedSubs(N_TICKET, "pbt_", 20 ether, true);
        _assertInvariant("after subscribes (nothing bought at signup)");

        // Daily STAGE: every funded lootbox sub buys a pending box; ticket subs buy tickets. The
        // purchases precede the day's request, so they are observable there.
        _stampToRequest(uint256(keccak256("pb_w1")) | 1);
        _assertInvariant("after the first daily STAGE purchase");
        assertGe(_pendingBoxCount(), N_LOOTBOX, "the lootbox subs' daily boxes are pending");

        // The day's cohort opens the stamped boxes as its AFKing read consumer. The engine is
        // stepped in minimal checkpoints with the invariant checked after every one; when the
        // AFKing stage is the next work, partial drains run through bounded mineFlip calls (a
        // starved, then a moderate, then a 2M gas allowance).
        _drainDay(uint256(keccak256("pb_c1")) | 1, true);
        _assertInvariant("after the full drain");
        assertEq(_pendingBoxCount(), 0, "fully drained ring has zero pending boxes");

        // Updates wait for the paid box; rejection preserves the exact count.
        _stampToRequest(uint256(keccak256("pb_w2")) | 1);
        _assertInvariant("after the second daily STAGE purchase");
        address cancelled = lootboxSubs[0];
        assertTrue(_boxPending(cancelled), "the paid box is pending");
        vm.prank(cancelled);
        vm.expectRevert(bytes4(keccak256("RngLocked()")));
        game.subscribe(0, false, 0, 0);
        _assertInvariant("pending cancellation rejected");

        _drainDay(uint256(keccak256("pb_c2")) | 1, false);
        _assertInvariant("after draining (incl. the rejected cancel's box)");
        assertEq(_pendingBoxCount(), 0, "the paid box opened; nothing pending");
        assertFalse(_boxPending(cancelled), "the cancelled sub's pending box was still opened");

        uint256 members = uint256(vm.load(address(game), bytes32(uint256(GameSlots.SUBSCRIBERS))));
        vm.prank(cancelled);
        game.subscribe(0, false, 0, 0);
        _assertInvariant("post-open cancellation");
        assertEq(uint256(vm.load(address(game), bytes32(uint256(GameSlots.SUBSCRIBERS)))), members - 1, "removed at once");

        // The next STAGE runs without the cancelled member; re-subscribe and purchase again.
        _stampToRequest(uint256(keccak256("pb_w3")) | 1);
        _drainDay(uint256(keccak256("pb_c3")) | 1, false);
        _assertInvariant("after the next STAGE");
        uint256 seat = _grantSeat(cancelled);
        vm.prank(cancelled);
        game.subscribe(0, false, 1, seat);
        _assertInvariant("after re-subscribing the cancelled sub");
        _stampToRequest(uint256(keccak256("pb_w4")) | 1);
        _assertInvariant("after the post-re-subscribe STAGE purchase");
        _drainDay(uint256(keccak256("pb_c4")) | 1, false);
        _assertInvariant("after the final full drain");
        assertEq(_pendingBoxCount(), 0, "final state: zero pending boxes");
    }

    // ---- engine driving ----

    /// @dev Settle the current day, move to the next, and step the engine in minimal checkpoints
    ///      through the day's subscriber preparation until its daily request is the next work.
    function _stampToRequest(uint256 vrfWord) internal {
        _drainDay(vrfWord ^ 0xF00D, false);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        for (uint256 i; i < 400; ++i) {
            _assertInvariant("preparation checkpoint");
            if (game.nextMinerAction() == 16) return; // MinerAction.RequestDaily
            _stepMinimal();
        }
        revert("harness: the daily request never became the next work");
    }

    /// @dev Step the engine in minimal checkpoints, answering requests, until it is idle with the
    ///      read cohort complete; the invariant is checked after every checkpoint. With `partialDrain`,
    ///      the first time the AFKing stage is the next work it is partially drained through
    ///      bounded mineFlip calls before the stepping continues.
    function _drainDay(uint256 vrfWord, bool partialDrain) internal {
        _captureCohort();
        bool partialUsed = !partialDrain;
        for (uint256 i; i < 800; ++i) {
            _assertInvariant("engine checkpoint");
            if (!game.advanceDue() && game.rngComplete()) {
                _assertCohortSettled();
                return;
            }
            _fulfillPending(vrfWord + i);
            if (!partialUsed && game.nextMinerAction() == 8) { // MinerAction.Afking
                partialUsed = true;
                uint256 before = _pendingBoxCount();
                uint256 starved = _oneBoxBudget();
                _trackedFlip(makeAddr("pb_drain_a"), starved);
                _assertInvariant("after a starved engine drain");
                assertEq(_pendingBoxCount(), before - 1, "the starved engine call opened exactly one box");
                _trackedFlip(makeAddr("pb_drain_b"), 1_500_000);
                _assertInvariant("after a moderate engine drain");
                if (game.nextMinerAction() == 8) {
                    _trackedFlip(makeAddr("pb_crank"), 2_000_000);
                    _assertInvariant("after a rewarded mineFlip drain");
                }
                continue;
            }
            if (game.advanceDue()) _stepMinimal();
        }
        revert("harness: the day never settled");
    }

    /// @dev The smallest mineFlip allowance that opens an AFKing box (bisection over snapshots).
    function _oneBoxBudget() internal returns (uint256) {
        uint256 before = _pendingBoxCount();
        uint256 lo = 100_000;
        uint256 hi = 30_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            uint256 snap = vm.snapshotState();
            (bool ok,) = address(game).call{gas: mid}(abi.encodeWithSignature("mineRun(uint32)", uint32(0)));
            bool opened = ok && _pendingBoxCount() < before;
            vm.revertToStateAndDelete(snap);
            if (opened) hi = mid;
            else lo = mid;
        }
        return hi;
    }

    /// @dev Maximum calibration preserves one checkpoint and records every AFKing settlement.
    function _stepMinimal() internal {
        _trackedFlip(address(this), 30_000_000, type(uint32).max);
    }

    // ---- settlement evidence (independent of the counter and cursor) ----

    bytes32 private constant LOOTBOX_OPENED = keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)");
    bytes32 private constant BOX_SPIN = keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)");
    bytes32 private constant CRAPS_PASSES = keccak256("LootBoxCrapsPasses(uint32,uint32,uint32,uint24)");

    uint32[] private _cohort;
    mapping(uint32 => uint256) private _settledCalls;
    uint32[] private _settledIds;

    /// @dev Record the boxes this cohort bought and has not opened.
    function _captureCohort() internal {
        delete _cohort;
        if (_pendingBoxCount() == 0) return;
        uint256 len = uint256(vm.load(address(game), bytes32(uint256(SUBSCRIBERS_SLOT))));
        for (uint256 i; i < len; ++i) {
            uint32 id = _memberAt(i);
            if (GameSlotKeys.afkingBoxPending(address(game), id)) _cohort.push(id);
        }
    }

    /// @dev One mineFlip; a call made while AFKing opens are the next read work has its settlement
    ///      records tallied, each account counted once per call.
    function _trackedFlip(address caller, uint256 gasCap) internal {
        _trackedFlip(caller, gasCap, 0);
    }

    function _trackedFlip(address caller, uint256 gasCap, uint32 multiplier) internal {
        bool afking = game.rngConsumerStage_g379() == 2;
        if (afking) vm.recordLogs();
        if (caller != address(this)) vm.prank(caller);
        game.mineRun{gas: gasCap}(multiplier);
        if (!afking) return;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint32[] memory seen = new uint32[](logs.length);
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            bytes32 sig = logs[i].topics[0];
            if (sig != LOOTBOX_OPENED && sig != BOX_SPIN && sig != CRAPS_PASSES) continue;
            uint32 id = uint32(uint256(logs[i].topics[1]));
            bool dup;
            for (uint256 j; j < n; ++j) if (seen[j] == id) dup = true;
            if (dup) continue;
            seen[n++] = id;
            if (_settledCalls[id]++ == 0) _settledIds.push(id);
        }
    }

    /// @dev Every stamped box settled in exactly one call, and nothing else settled as AFKing.
    function _assertCohortSettled() internal {
        for (uint256 i; i < _cohort.length; ++i) {
            assertEq(_settledCalls[_cohort[i]], 1, "each stamped box settles exactly once");
        }
        for (uint256 i; i < _settledIds.length; ++i) {
            uint32 id = _settledIds[i];
            bool stamped;
            for (uint256 j; j < _cohort.length; ++j) if (_cohort[j] == id) stamped = true;
            assertTrue(stamped, "only stamped boxes settle in the AFKing stage");
            delete _settledCalls[id];
        }
        delete _settledIds;
        delete _cohort;
    }

    // ---- invariant core ----

    /// @dev The count never exceeds the box members ahead of the opener cursor (a protocol seat
    ///      counts only once it bought into the cohort).
    function _assertInvariant(string memory label) internal view {
        assertLe(
            _pendingBoxCount(),
            _countPendingMarkers(),
            string(abi.encodePacked("_pendingBoxCount exceeds the boxes ahead of the opener: ", label))
        );
    }

    function _pendingBoxCount() internal view returns (uint256) {
        return
            (uint256(vm.load(address(game), bytes32(CURSOR_SLOT))) >> PENDING_COUNT_SHIFT) &
            0xFFFF;
    }

    /// @dev Id at logical member index `i`: boxes first, then the ticket section from the top.
    function _memberAt(uint256 i) internal view returns (uint32) {
        uint256 packed = uint256(vm.load(address(game), bytes32(GameSlots.SUB_BOX_COUNT)));
        uint256 boxes = uint16(packed >> (GameSlots.SUB_BOX_COUNT_OFFSET * 8));
        uint256 position = i < boxes ? i : 2000 - (i - boxes);
        bytes32 base = keccak256(abi.encode(uint256(SUBSCRIBERS_SLOT)));
        uint256 word = uint256(vm.load(address(game), bytes32(uint256(base) + position / 3)));
        return uint32((word >> ((position % 3) * 85)) & 0xFFFFFFFF);
    }

    function _boxPending(address who) internal view returns (bool) {
        return GameSlotKeys.afkingBoxPending(address(game), game.walletIdOf_g3120(who));
    }

    function _countPendingMarkers() internal view returns (uint256 pending) {
        uint256 len = uint256(vm.load(address(game), bytes32(uint256(SUBSCRIBERS_SLOT))));
        for (uint256 i; i < len; ++i) {
            if (GameSlotKeys.afkingBoxPending(address(game), _memberAt(i))) ++pending;
        }
    }

    // ---- fixture helpers (ported from OpenWalkCompositionGas / V56AfkingGasMarginal) ----

    function _pokePendingCount(uint16 pendingCount) internal {
        uint256 w = uint256(vm.load(address(game), bytes32(CURSOR_SLOT)));
        w = (w & ~(uint256(0xFFFF) << PENDING_COUNT_SHIFT)) | (uint256(pendingCount) << PENDING_COUNT_SHIFT);
        vm.store(address(game), bytes32(CURSOR_SLOT), bytes32(w));
    }

    function _setupFundedSubs(uint256 n, string memory prefix, uint256 poolEach, bool isTicket)
        internal
        returns (address[] memory subs)
    {
        subs = new address[](n);
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            uint256 seat = _grantSeat(who);
            _fundPool(who, poolEach);
            vm.prank(who);
            game.subscribe(0, isTicket, 1, seat);
        }
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        uint32 id = game.walletIdOf_g3120(who);
        if (id == 0) id = _giveWalletId(who);
        game.depositAfkingFunding{value: amount}(id);
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
