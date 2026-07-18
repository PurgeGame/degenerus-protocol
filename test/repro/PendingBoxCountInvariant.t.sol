// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";

/// @title PendingBoxCountInvariant — `_pendingBoxCount` == Σ pending day-markers, everywhere
/// @notice The `_pendingBoxCount` counter (DegenerusGameStorage slot 58, bits [224,240)) gates
///         the rewarded open crank's afking ring walk: it MUST equal the number of subscribers
///         whose `lastOpenedDay < lastAutoBoughtDay` (a stamped-but-unopened box) after EVERY
///         lifecycle transition, or the gate under-counts (walk skipped with real work pending —
///         boxes then wait for the counter-blind openBoxes valve) or over-counts (walks that
///         find nothing — gas only). Exactness rests on the no-orphan rule: a pending sub is
///         never re-stamped, evicted, reclaimed, or funding-killed, so the daily STAGE lootbox
///         stamp is the ONLY increment and the box open the ONLY decrement.
/// @dev Walks the full live `_subscribers` ring via vm.load after each step and compares.
///      Covers: grounded subscribe (lootbox + ticket mode), the daily STAGE stamp, partial and
///      full drains (valve + rewarded crank), cancel-to-tombstone WHILE PENDING (markers
///      retained, box still opened in-set), tombstone reclaim, and re-subscribe. Pass-expiry
///      eviction is not driven here: the no-orphan guard makes it unreachable while pending,
///      and a box-clean evict never touches the counter (see GameAfkingModule stage loop).
contract PendingBoxCountInvariant is DeployProtocol {
    uint256 private constant SUBOF_SLOT = 53;
    uint256 private constant SUBSCRIBERS_SLOT = 55;
    uint256 private constant CURSOR_SLOT = 57;
    uint256 private constant PENDING_COUNT_SHIFT = 224;
    uint256 private constant OFF_LASTBOUGHT = 7;  // uint24 lastAutoBoughtDay (bytes 7..9)
    uint256 private constant OFF_LASTOPENED = 10; // uint24 lastOpenedDay     (bytes 10..12)
    uint256 private _lastFulfilledReqId;

    uint256 private constant N_LOOTBOX = 12;
    uint256 private constant N_TICKET = 4;

    function setUp() public {
        _deployProtocol();
        // Advance one day off the deploy boundary so the day index is a clean, stable index.
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 10_000_000 ether);
    }

    function testPendingBoxCountTracksMarkersAcrossLifecycle() public {
        _assertInvariant("fresh deploy");

        // Grounded subscribes: lootbox-mode cover-buys ride the indexed human queue and mark
        // themselves box-clean; ticket-mode buys are always box-clean. Counter stays 0.
        address[] memory lootboxSubs = _setupFundedSubs(N_LOOTBOX, "pbl_", 20 ether, false);
        _setupFundedSubs(N_TICKET, "pbt_", 20 ether, true);
        _assertInvariant("after grounded subscribes (cover-buys are box-clean)");

        // Daily STAGE: every funded lootbox sub gets a Sub-stamp box (pending); ticket subs
        // stamp box-clean.
        _runStageNewDay(uint256(keccak256("pb_w1")) | 1);
        _settleClean(uint256(keccak256("pb_c1")) | 1);
        _assertInvariant("after the first daily STAGE stamp");
        assertGe(_pendingBoxCount(), N_LOOTBOX, "the lootbox subs' daily boxes are pending");

        // Partial drain through the counter-blind valve, one box at a time.
        vm.prank(makeAddr("pb_drain_a"));
        game.openBoxes(1);
        _assertInvariant("after a 1-box valve drain");
        vm.prank(makeAddr("pb_drain_b"));
        game.openBoxes(3);
        _assertInvariant("after a 3-box valve drain");

        // Rewarded crank (counter-gated path) drains more.
        if (!game.advanceDue() && !game.rngLocked()) {
            vm.prank(makeAddr("pb_crank"));
            game.mintFlip();
            _assertInvariant("after a rewarded mintFlip drain");
        }

        // Full drain to zero.
        vm.prank(makeAddr("pb_drain_c"));
        game.openBoxes(2000);
        _assertInvariant("after the full drain");
        assertEq(_pendingBoxCount(), 0, "fully drained ring has zero pending boxes");

        // Cancel WHILE PENDING: stamp a fresh day, then cancel one lootbox sub before its box
        // opens. The cancel tombstones in-set and retains the markers (no-orphan rule), so the
        // counter must still include the tombstone's box — and the open walk must still open it.
        _runStageNewDay(uint256(keccak256("pb_w2")) | 1);
        _settleClean(uint256(keccak256("pb_c2")) | 1);
        _assertInvariant("after the second daily STAGE stamp");
        address cancelled = lootboxSubs[0];
        if (!(_lastOpenedDayOf(cancelled) < _lastBoughtDayOf(cancelled))) {
            // Later game phases can deliver a lootbox sub's daily buy as a (box-clean) ticket
            // buy, so re-arm the pending state deterministically: mark the sub pending on its
            // already-worded stamp day and bump the counter to match — byte-identical to the
            // state a daily Sub-stamp box leaves behind.
            uint32 d = _lastBoughtDayOf(cancelled);
            require(_rngWordByDay(d) != 0, "fixture: the stamp-day word landed");
            _pokeSubOpenedDay(cancelled, d - 1);
            _pokePendingCount(uint16(_pendingBoxCount() + 1));
            _assertInvariant("after re-arming a pending box via poke");
        }
        vm.prank(cancelled);
        game.subscribe(address(0), false, false, 0, address(0)); // qty 0 = cancel (tombstone)
        _assertInvariant("after cancelling a sub with a pending box (tombstone retains markers)");

        vm.prank(makeAddr("pb_drain_d"));
        game.openBoxes(2000);
        _assertInvariant("after draining (incl. the pending tombstone's box)");
        assertEq(_pendingBoxCount(), 0, "tombstone's box opened; nothing pending");
        assertEq(
            _lastOpenedDayOf(cancelled),
            _lastBoughtDayOf(cancelled),
            "the cancelled sub's pending box was still opened in-set"
        );

        // Next STAGE reclaims the (now box-clean) tombstone; re-subscribe and stamp again.
        _runStageNewDay(uint256(keccak256("pb_w3")) | 1);
        _settleClean(uint256(keccak256("pb_c3")) | 1);
        _assertInvariant("after the tombstone-reclaim STAGE");
        vm.prank(cancelled);
        game.subscribe(address(0), false, false, 1, address(0));
        _assertInvariant("after re-subscribing the reclaimed sub");
        _runStageNewDay(uint256(keccak256("pb_w4")) | 1);
        _settleClean(uint256(keccak256("pb_c4")) | 1);
        _assertInvariant("after the post-re-subscribe STAGE stamp");
        vm.prank(makeAddr("pb_drain_e"));
        game.openBoxes(2000);
        _assertInvariant("after the final full drain");
        assertEq(_pendingBoxCount(), 0, "final state: zero pending boxes");
    }

    // ---- invariant core ----

    function _assertInvariant(string memory label) internal view {
        assertEq(
            _pendingBoxCount(),
            _countPendingMarkers(),
            string(abi.encodePacked("_pendingBoxCount != pending-marker walk: ", label))
        );
    }

    function _pendingBoxCount() internal view returns (uint256) {
        return
            (uint256(vm.load(address(game), bytes32(CURSOR_SLOT))) >> PENDING_COUNT_SHIFT) &
            0xFFFF;
    }

    function _countPendingMarkers() internal view returns (uint256 pending) {
        uint256 len = uint256(vm.load(address(game), bytes32(uint256(SUBSCRIBERS_SLOT))));
        bytes32 base = keccak256(abi.encode(uint256(SUBSCRIBERS_SLOT)));
        for (uint256 i; i < len; ++i) {
            address who = address(uint160(uint256(vm.load(address(game), bytes32(uint256(base) + i)))));
            if (_lastOpenedDayOf(who) < _lastBoughtDayOf(who)) {
                unchecked {
                    ++pending;
                }
            }
        }
    }

    // ---- fixture helpers (ported from OpenWalkCompositionGas / V56AfkingGasMarginal) ----

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTOPENED, 24));
    }

    function _rngWordByDay(uint32 day) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(day), uint256(10)))));
    }

    function _pokeSubOpenedDay(address who, uint32 d) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 w = uint256(vm.load(address(game), slot));
        uint256 shift = OFF_LASTOPENED * 8;
        w = (w & ~(uint256(0xFFFFFF) << shift)) | (uint256(d & 0xFFFFFF) << shift);
        vm.store(address(game), slot, bytes32(w));
    }

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
            _grantSeat(who); // the AFKing Subscription Token is the subscribe credential (NoCoin without it)
            _fundPool(who, poolEach);
            vm.prank(who);
            game.subscribe(address(0), false, isTicket, 1, address(0));
        }
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < 60; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
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
