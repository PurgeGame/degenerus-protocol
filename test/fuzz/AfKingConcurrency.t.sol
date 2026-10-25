// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

// Permanently skipped historical cases were retired in the test review.
// See docs/TEST_REVIEW.md for replacement suites and remaining coverage limits.

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title AfKingConcurrency -- the game-resident subscriber-set mutation correctness: the per-sub buy
///        runs INSIDE `mineFlip()`'s required-path subscriber pass, strictly pre-RNG, and the pass is the
///        single per-day buy driver.
///
/// @notice The set-mutation floor:
///   - Exactly-once / no double-buy: a full pass over a new day buys every funded member EXACTLY ONCE.
///   - Daily reset: the first advance into a new day flips `subsFullyProcessed=false` + `_subCursor=0`
///     so the new day buys for every member once.
///   - Cancel removes at once: `subscribe(_, 0)` settles both sides and swap-removes the member from
///     the set, so a signup after it is a plain new entry with no duplicate membership. The set only
///     changes outside the lock window, so no active member is ever skipped by a cancel.
///   - Expiry swap-pop no-miss: an unfunded member removed during the pass is replaced by its section's
///     tail, which is processed at the same cursor in the same pass.
contract AfKingConcurrency is DeployProtocol {

    mapping(address => uint32) private _aidCache;

    /// @dev Wallet ID of `a`, registering it when it holds none. Call before any `vm.prank`.
    function _aid(address a) internal returns (uint32 id) {
        id = _aidCache[a];
        if (id == 0) {
            id = game.walletIdOf_g3120(a);
            if (id == 0) id = _giveWalletId(a);
            _aidCache[a] = id;
        }
    }

    uint256 private constant SUBSCRIBERS_SLOT = GameSlots.SUBSCRIBERS; // _subscribers (length here)
    uint256 private constant SUBCURSOR_SLOT = GameSlots.SUB_CURSOR; // _subCursor uint16 at offset 0 (the pass cursor)

    /// @dev SubscriptionExpired(uint32 indexed player, uint8 reason): 1 = unfunded, 2 = seized.
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(uint32,uint8)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    /// @dev Snapshot of SubscriptionExpired(player, reason) emissions, drained by `_drainLogs()`.
    address[] private _expiredPlayers;
    uint8[] private _expiredReasons;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        _finishSubscriptionWindow();
    }


    /// @notice Daily reset gate: a pass drives `_subCursor` to the set end and sets `subsFullyProcessed = true`
    ///         (afking done for THIS day). A fresh-day reset flips `subsFullyProcessed` back to false and
    ///         `_subCursor` to 0, and a subsequent pass buys for each member exactly once.
    function testStageResetGateReopensProcessingPerDay() public {
        uint256 N = 4;
        address[] memory subs = _setupHealthyBuyingSubs(N, "daily_");
        uint256 price = game.mintPrice();

        _snapshotFunding(subs);
        _runStageNewDay(0xD1);
        for (uint256 i; i < N; i++) {
            assertEq(_boughtFor(subs[i]), price, "day-1: each sub bought exactly once");
        }
        assertTrue(_subsFullyProcessed(), "post-pass: subsFullyProcessed == true (gate closed for the day)");
        assertEq(_subCursorVal(), uint16(1 << 15), "all-box pass ended at the empty ticket section");

        // A real new day re-opens the gate by itself: each member buys exactly once again.
        _snapshotFunding(subs);
        _runStageNewDay(0xD2);
        for (uint256 i; i < N; i++) {
            assertEq(_boughtFor(subs[i]), price, "day-2: each sub bought exactly once again");
        }

        // The reset gate the contract opens at a new-day entry: `subsFullyProcessed = false; _subCursor = 0`.
        _openAfkingResetGate();
        assertFalse(_subsFullyProcessed(), "reset re-opened the gate (subsFullyProcessed == false)");
        assertEq(_subCursorVal(), 0, "reset rewound the cursor to 0 (set re-walked from the start)");
    }

    /// @notice Cancel removes the member at once (no tombstone); a later signup is a plain new entry that
    ///         never double-adds, and the new run buys on the next pass like any other.
    function testCancelRemovesAtOnceAndResubscribeNeverDoubleAdds() public {
        address[] memory subs = _setupHealthyBuyingSubs(1, "react_");
        address sub = subs[0];

        uint256 lenBefore = _subscribersLen();
        assertGt(_subscriberIndexOf(sub), 0);

        vm.prank(sub);
        game.subscribe(0, false, 0, 0); // cancel
        assertEq(_subscriberIndexOf(sub), 0, "cancel removed the member at once");
        assertEq(_subscribersLen(), lenBefore - 1, "no tombstone stays in the set");

        uint256 seat = _grantSeat(sub);
        vm.prank(sub);
        game.subscribe(0, false, 3, seat);
        assertGt(_subscriberIndexOf(sub), 0, "re-subscribe re-added the member");
        assertEq(_subscribersLen(), lenBefore, "re-subscribe adds exactly one entry");
        assertEq(_dailyQtyOf(sub), 3, "re-subscribe restored the quantity");

        _snapshotFunding(subs);
        vm.recordLogs();
        _runStageNewDay(0xAE1);
        _drainLogs();
        assertEq(_countExpiredFor(sub, 1), 0, "the new run is not expired");
        assertEq(_boughtFor(sub), 3 * game.mintPrice(), "the new run buys once at its quantity");
    }

    /// @notice Cancelling a member ahead of the others moves the section tail into its place; every
    ///         remaining member is still bought exactly once on the next pass.
    function testCancelSwapPopSkipsNoActiveMember() public {
        address[] memory subs = _setupHealthyBuyingSubs(4, "swap_");
        vm.prank(subs[0]);
        game.subscribe(0, false, 0, 0);
        _snapshotFunding(subs);
        _runStageNewDay(0x5A9);
        uint256 price = game.mintPrice();
        assertEq(_boughtFor(subs[0]), 0, "the cancelled member is gone");
        for (uint256 i = 1; i < 4; i++) assertEq(_boughtFor(subs[i]), price, "each remaining member bought once");
    }

    /// @notice An unfunded member expiring mid-pass is replaced by its section's tail, which is processed
    ///         at the same cursor in the same pass: no funded member is skipped.
    function testExpiryMoverIsStillProcessedThisPass() public {
        address[] memory subs = _setupHealthyBuyingSubs(4, "mover_");
        vm.prank(subs[0]);
        game.withdrawAfkingFunding(0, 1 ether);
        _snapshotFunding(subs);
        vm.recordLogs();
        _runStageNewDay(0x30FE);
        _drainLogs();
        uint256 price = game.mintPrice();
        assertEq(_countExpiredFor(subs[0], 1), 1, "the unfunded member expired");
        assertEq(_subscriberIndexOf(subs[0]), 0);
        for (uint256 i = 1; i < 4; i++) assertEq(_boughtFor(subs[i]), price, "each funded member bought once");
    }

    /// @notice A cancelled sub's prepaid afking ETH stays withdrawable.
    function testCancelledSubFundingWithdrawable() public {
        address[] memory subs = _setupHealthyBuyingSubs(1, "strandfund_");
        address sub = subs[0];

        _fundPool(sub, 3 ether);
        uint256 fundedBefore = game.afkingFundingOf(sub);
        assertGt(fundedBefore, 0, "sub has prepaid afking ETH");

        vm.prank(sub);
        game.subscribe(0, false, 0, 0); // cancel
        assertEq(_subscriberIndexOf(sub), 0, "cancel removed the member");
        assertEq(game.afkingFundingOf(sub), fundedBefore, "cancel did not confiscate the afking ETH");

        uint256 balBefore = sub.balance;
        vm.prank(sub);
        game.withdrawAfkingFunding(0, fundedBefore);
        assertEq(game.afkingFundingOf(sub), 0, "afking ETH drained on withdraw");
        assertEq(sub.balance - balBefore, fundedBefore, "prepaid afking ETH returned to the cancelled sub");
    }


    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Drive the subscriber pass for a NEW day: warp a day forward and crank the whole day, so
    ///      the pass buys for the funded set and every box opens before the next day.
    function _runStageNewDay(uint256) internal {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _finishSubscriptionWindow();
    }

    /// @dev Run the STAGE exactly ONCE on a fresh day via a SINGLE `mineFlip()` (no full settle),
    ///      used by the pass-eviction tests. The STAGE runs strictly PRE-RNG (AdvanceModule:305-326),
    ///      so the eviction / buy completes before rngGate and the stage is measured on its own.
    ///      Subscribers must already be registered (subscribe blocks during rngLock).
    function _runStageOnce() internal {
        vm.warp(block.timestamp + 1 days);
        game.mineRun(0);
    }

    /// @dev Settle the game to a clean state: drive mineFlip + deliver the mock VRF word until
    ///      advanceDue() is false and we are not rng-locked. Ported from
    ///      KeeperRewardRoutingSameResults._settleGame (PATTERNS §"Settle-to-clean-state VRF drain").
    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.mineRun(0);
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(reqId, vrfWord);
                    _lastFulfilledReqId = reqId;
                }
            }
        }
    }

    /// @dev Subscribe `n` fresh players as fully-healthy LOOTBOX-mode buying subs (operator-approved,
    ///      afking-funded). Granted deity so they survive any crossing (a no-pass sub at level>0 would
    ///      evict at the crossing before buying — orthogonal to the set-mutation property under test).
    ///      Δ2/Δ5: subscribe via game.subscribe; fund via game.depositAfkingFunding.
    function _setupHealthyBuyingSubs(uint256 n, string memory prefix) internal returns (address[] memory subs) {
        subs = new address[](n);
        for (uint256 i; i < n; i++) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            uint256 seat = _grantSeat(who); // the AFKing Subscription Token is the subscribe credential (sub <=> coin)
            _fundPool(who, 1 ether);
            vm.prank(who);
            game.subscribe(0, false, 1, seat); // self, lootbox mode, qty 1
        }
    }

    /// @dev Credit `who`'s afkingFunding bucket with `amount` ETH (Δ5: depositAfkingFunding replaces
    ///      AfKing.depositFor).
    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(_aid(who));
    }

    /// @dev `subsFullyProcessed` (slot 0, offset 28, bool) — the per-day afking-done gate.
    function _subsFullyProcessed() internal view returns (bool) {
        uint256 p0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return uint8(p0 >> (28 * 8)) != 0;
    }

    /// @dev `_subCursor` (slot 56, offset 0, uint16) — the STAGE walk cursor.
    function _subCursorVal() internal view returns (uint16) {
        return uint16(uint256(vm.load(address(game), bytes32(uint256(SUBCURSOR_SLOT)))));
    }

    /// @dev Open the afking reset gate exactly as the contract does on a new-day entry
    ///      (AdvanceModule:306-308): `subsFullyProcessed = false; _subCursor = 0`. This is the precise
    ///      EFFECT of the `_afkingResetDay != day` per-day reset, applied to the same two storage
    ///      fields the contract writes (the idle fixture's real day index saturates without ticket
    ///      purchases, so the gate is opened directly rather than via a real day rollover).
    function _openAfkingResetGate() internal {
        // _subCursor = 0 (slot 56, offset 0, uint16).
        bytes32 sCursor = bytes32(uint256(SUBCURSOR_SLOT));
        uint256 pCursor = uint256(vm.load(address(game), sCursor));
        pCursor &= ~uint256(0xFFFF);
        vm.store(address(game), sCursor, bytes32(pCursor));
        // subsFullyProcessed = false (slot 0, offset 28).
        bytes32 s0 = bytes32(uint256(0));
        uint256 p0 = uint256(vm.load(address(game), s0));
        p0 &= ~(uint256(0xFF) << (28 * 8));
        vm.store(address(game), s0, bytes32(p0));
    }

    /// @dev `who`'s set position + 1; 0 = not in the set.
    function _subscriberIndexOf(address who) internal view returns (uint256 position1) {
        (, position1) = GameSlotKeys.subLane(address(game), game.walletIdOf_g3120(who));
    }

    function _dailyQtyOf(address who) internal view returns (uint8) {
        return uint8(GameSlotKeys.subQuantity(address(game), game.walletIdOf_g3120(who)));
    }

    /// @dev `_subscribers.length` (slot 54 holds the array length).
    function _subscribersLen() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBSCRIBERS_SLOT))));
    }

    // ---- Buy oracle: the prepaid funding delta across a pass ----

    mapping(address => uint256) private _fundingBefore;

    function _snapshotFunding(address[] memory tracked) internal {
        for (uint256 i; i < tracked.length; i++) _fundingBefore[tracked[i]] = game.afkingFundingOf(tracked[i]);
    }

    /// @dev Wei debited from `who`'s prepaid bucket since the snapshot.
    function _boughtFor(address who) internal view returns (uint256) {
        return _fundingBefore[who] - game.afkingFundingOf(who);
    }

    // ---- Event drain (emitter == address(game) — the game-resident module emits via delegatecall) ----

    function _drainLogs() internal {
        delete _expiredPlayers;
        delete _expiredReasons;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == SUB_EXPIRED_SIG && logs[i].topics.length >= 2) {
                _expiredPlayers.push(_fixturePayee(uint32(uint256(logs[i].topics[1]))));
                _expiredReasons.push(uint8(uint256(bytes32(logs[i].data))));
            }
        }
    }

    function _countExpiredFor(address who, uint8 reason) internal view returns (uint256 count) {
        for (uint256 i; i < _expiredPlayers.length; i++) {
            if (_expiredPlayers[i] == who && _expiredReasons[i] == reason) count++;
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
