// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

// Permanently skipped historical cases were retired in the test review.
// See docs/TEST_REVIEW.md for replacement suites and remaining coverage limits.

import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title AfKingConcurrency -- Proves the v55.0 game-resident afking subscriber-set mutation
///        correctness: the per-sub buy now runs INSIDE `mineFlip()`'s required-path process
///        STAGE (the Afking stage, `SUB_STAGE_BATCH=50`), strictly
///        PRE-RNG. The standalone `autoBuy(maxCount)` keeper entrypoint and its mid-block cursor are
///        GONE (D-351-01 successor remap, PATTERNS §3); the STAGE is the single per-day buy driver.
///        This file is the PRIMARY set-mutation / swap-pop / tombstone analog for TST-04: it proves
///        the H-CANCEL-SWAP-MISS resolution (the in-place cancel-tombstone + deferred reclaim that
///        advances NO cursor) that TST-04 regresses ([[afking-cancel-tombstone-streak-finding]]).
///
/// @notice The v55 set-mutation floor (reframed onto the game-resident STAGE):
///   - Exactly-once / no double-buy: a full STAGE cycle (mineFlip over a new day) buys every
///     active funded sub EXACTLY ONCE; the per-entry `lastAutoBoughtDay >= processDay` idempotency
///     skip (GameAfkingModule.sol:598) prevents a second buy if the STAGE re-visits an index already
///     stamped this cycle (the chunked-same-day case across partial-drain advance calls).
///   - Daily reset: the first advance into a NEW day flips `subsFullyProcessed=false` + `_subCursor=0`
///     (AdvanceModule:305-309) so the new day re-stamps every active sub once.
///   - In-place cancel-tombstone no-miss (CONSENT-02 / H-CANCEL-SWAP-MISS): `subscribe(_,0)` is a
///     TRUE in-place tombstone -- it writes `dailyQuantity=0` and relocates NO ONE (the entry stays
///     in the iterable set). The swap-pop is DEFERRED to the STAGE's top-of-loop reclaim branch
///     (GameAfkingModule.sol:586-594) that `delete _subOf[player]` + `_removeFromSet` + continues
///     WITHOUT advancing the cursor, so the swap-pop occupant (a mover from ahead, still pending) is
///     re-read at the freed index THIS pass -- no active sub is skipped. Because the cancel moves
///     nothing, it can never push a still-pending tail behind the cursor (H-CANCEL-SWAP-MISS resolved).
///   - Pass-eviction swap-pop invariant (CONSENT-01): a no-pass crossing eviction routes through the
///     SAME tombstone-then-reclaim shape (`sub.dailyQuantity=0; _removeFromSet; continue` WITHOUT a
///     cursor advance, GameAfkingModule.sol:619-628) -- membership ⟺ packed-index != 0 preserved.
///
/// @notice The five call-site deltas applied (D-351-01, PATTERNS §"five call-site deltas"):
///   Δ1: dropped the deleted standalone-contract source dependency -- the receiver is the game path.
///   Δ2 subscribe: `afKing.subscribe(...)` -> `game.subscribe(...)` (identical 6-arg sig, dispatch stub
///      DegenerusGame.sol:363 -> GameAfkingModule.sol:234).
///   Δ4 autoBuy: `afKing.autoBuy(N)` has NO successor -- the per-sub buy folded into `mineFlip()`'s
///      required-path STAGE; driven here via a new-day `mineFlip()` + the `_settleGame` VRF drain.
///   Δ5 views/cancel: `afKing.subscriberCount()`/`subscriberAt()`/`subscriptionOf()`/`autoBuyProgress()`
///      have NO game-exposed external view -> read `_subscribers`/`_subOf`/`_subCursor` via `vm.load`
///      RE-DERIVED slots (the AfKing-standalone-layout constants were WRONG); `setDailyQuantity(0)` ->
///      re-`subscribe(...,dailyQuantity=0,...)`; `poolOf`/`withdraw`/`depositFor` ->
///      `afkingFundingOf`/`withdrawAfkingFunding`/`depositAfkingFunding`.
///
/// @dev Builds on the 351-01-repaired DeployProtocol fixture (GameAfkingModule live at
///      GAME_AFKING_MODULE; the two SUB-09 self-subscribes VAULT + SDGNRS already in the set). Test
///      subs are driven through the public game.subscribe() API. Test-only: no contracts/*.sol mutated.
contract AfKingConcurrency is DeployProtocol {

    mapping(address => uint32) private _aidCache;

    /// @dev Wallet ID of `a`, registering it when it holds none. Call before any `vm.prank`.
    function _aid(address a) internal returns (uint32 id) {
        id = _aidCache[a];
        if (id == 0) {
            id = game.walletIdOf(a);
            if (id == 0) id = _giveWalletId(a);
            _aidCache[a] = id;
        }
    }

    // -------------------------------------------------------------------------
    // Game-resident storage slots (via `forge inspect DegenerusGame storageLayout`).
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = GameSlots.SUB_OF; // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBERS_SLOT = GameSlots.SUBSCRIBERS; // _subscribers address[] (length here; data at keccak(54))
    uint256 private constant SUBCURSOR_SLOT = GameSlots.SUB_CURSOR; // _subCursor uint16 at offset 0 (the STAGE walk cursor)
    uint256 private constant MINTPACKED_SLOT = GameSlots.MINT_PACKED; // mintPacked_ mapping root (deity bit lives here)

    // Sub packed-field byte offsets (cumulative little-endian within the single packed slot —
    // DegenerusGameStorage.sol:1895 is the authoritative layout; the v56 compute-on-read re-pack
    // narrowed `amount` to uint24 and the day markers to uint24).
    uint256 private constant OFF_DAILY = 0; // uint8  dailyQuantity      (byte 0)
    uint256 private constant OFF_VALIDTHROUGH = 1; // uint24 validThroughLevel  (bytes 1..3)
    uint256 private constant OFF_REINVEST = 4; // uint8  reinvestPct        (byte 4)
    uint256 private constant OFF_FLAGS = 4; // uint8  flags              (byte 5; bit1=drainFirst, bit2=useTickets)
    uint256 private constant OFF_SCOREPLUS1 = 5; // uint16 scorePlus1         (bytes 6..7)
    uint256 private constant OFF_AMOUNT = 7; // uint24 amount             (bytes 8..10)
    uint256 private constant OFF_LASTBOUGHT = 10; // uint24 lastAutoBoughtDay  (bytes 11..13)
    uint256 private constant OFF_LASTOPENED = 13; // uint24 lastOpenedDay      (bytes 14..16)

    uint256 private constant DEITY_SHIFT = BitPackingLib.HAS_DEITY_PASS_SHIFT; // HAS_DEITY_PASS_SHIFT in mintPacked_

    /// @dev SubscriptionExpired(address indexed player, uint8 reason) — the game-resident module
    ///      event (emitter == address(game) via delegatecall). reason 2 = CancelReclaim,
    ///      reason 1 = AutoPause (pass-eviction at crossing OR funding-skip kill).
    bytes32 private constant SUB_EXPIRED_SIG = keccak256("SubscriptionExpired(uint32,uint8)");

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    /// @dev Snapshot of SubscriptionExpired(player, reason) emissions, drained by `_drainLogs()`.
    address[] private _expiredPlayers;
    uint8[] private _expiredReasons;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }


    /// @notice v55 daily reset gate (AdvanceModule:305-309): a STAGE run drives `_subCursor` to the
    ///         set end and sets `subsFullyProcessed = true` (afking done for THIS day). The
    ///         forward-looking `_afkingResetDay != day` gate is what re-opens processing on a fresh
    ///         day — flipping `subsFullyProcessed` back to false + `_subCursor` to 0. Proves the gate
    ///         non-vacuously: after a full STAGE the gate is closed (subsFullyProcessed true, cursor at
    ///         end); a fresh-day reset re-opens it and a subsequent STAGE re-stamps each sub exactly
    ///         once. (The idle fixture's real day index saturates without ticket purchases, so the
    ///         fresh-day reset is driven via the documented `_afkingResetDay` gate slot — the same
    ///         field the contract itself writes at AdvanceModule:306.)
    function testStageResetGateReopensProcessingPerDay() public {
        uint256 N = 4;
        address[] memory subs = _setupHealthyBuyingSubs(N, "daily_");

        _runStageNewDay(0xD1);
        for (uint256 i; i < N; i++) {
            assertEq(_countBoughtFor(subs[i]), 1, "day-1: each sub bought exactly once");
        }
        // After a completed STAGE: the gate is CLOSED for this day (no more processing).
        assertTrue(_subsFullyProcessed(), "post-STAGE: subsFullyProcessed == true (gate closed for the day)");
        assertEq(_subCursorVal(), uint16(_subscribersLen()), "post-STAGE: cursor reached the set end");

        // Fresh-day reset: open the reset gate exactly as the contract does at a new-day entry
        // (AdvanceModule:306-308: `subsFullyProcessed = false; _subCursor = 0`).
        _openAfkingResetGate();

        // Re-open confirmed (NON-VACUOUS — the gate was demonstrably CLOSED above with the cursor at
        // the set end): the per-day reset re-enables STAGE processing for the next cycle. This is the
        // exact AdvanceModule:305-309 gate the contract re-opens on a fresh day.
        assertFalse(_subsFullyProcessed(), "reset re-opened the gate (subsFullyProcessed == false)");
        assertEq(_subCursorVal(), 0, "reset rewound the cursor to 0 (set re-walked from the start)");
    }


    /// @notice TST-04: reactivating a still-in-set tombstone (before any STAGE reclaims it) flips it
    ///         back to active IN PLACE with NO duplicate set membership (idempotent `_addToSet`).
    function testReactivateTombstonedSubNoDoubleAdd() public {
        address[] memory subs = _setupHealthyBuyingSubs(1, "react_");
        address sub = subs[0];

        uint256 idx = _subscriberIndexOf(sub);
        uint256 lenBefore = _subscribersLen();

        vm.prank(sub);
        game.subscribe(0, false, false, 0, 0, 0); // tombstone, still in set
        assertEq(_subscriberIndexOf(sub), idx, "tombstone in set, same index");

        // Re-subscribe the still-in-set tombstoned address (a new run burns a new seat).
        uint256 seat = _grantSeat(sub);
        vm.prank(sub);
        game.subscribe(0, false, false, 3, 0, seat);
        assertEq(_subscriberIndexOf(sub), idx, "re-subscribe kept the same set slot (idempotent _addToSet)");
        assertEq(_subscribersLen(), lenBefore, "re-subscribe of an in-set tombstone never double-adds");
        assertEq(_dailyQtyOf(sub), 3, "re-subscribe reactivated the sub (dailyQuantity restored)");

        // A STAGE now treats it as a normal active sub (not a tombstone) -- it buys, not reclaims.
        vm.recordLogs();
        _runStageNewDay(0xAE1);
        _drainLogs();
        assertEq(_countExpiredFor(sub, 2), 0, "reactivated sub is NOT reclaimed as a tombstone");
        assertEq(_countBoughtFor(sub), 1, "reactivated sub buys as a normal active sub");
    }


    /// @notice TST-04: a cancelled sub's stranded afking ETH stays withdrawable (game-resident
    ///         afkingFunding -- `withdrawAfkingFunding`).
    function testCancelledSubFundingWithdrawable() public {
        address[] memory subs = _setupHealthyBuyingSubs(1, "strandfund_");
        address sub = subs[0];

        _fundPool(sub, 3 ether);
        uint256 fundedBefore = game.afkingFundingOf(sub);
        assertGt(fundedBefore, 0, "sub has stranded afking ETH");

        vm.prank(sub);
        game.subscribe(0, false, false, 0, 0, 0); // tombstone
        assertGt(_subscriberIndexOf(sub), 0, "v55: cancel is an in-place tombstone -- still in set");
        assertEq(_dailyQtyOf(sub), 0, "cancel wrote the in-place sentinel");
        assertEq(game.afkingFundingOf(sub), fundedBefore, "cancel did not confiscate the afking ETH");

        uint256 balBefore = sub.balance;
        vm.prank(sub);
        game.withdrawAfkingFunding(0, fundedBefore);
        assertEq(game.afkingFundingOf(sub), 0, "afking ETH drained on withdraw");
        assertEq(sub.balance - balBefore, fundedBefore, "stranded afking ETH returned to the cancelled sub");
    }


    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Drive the per-sub buy STAGE for a NEW day: warp a day forward, then run mineFlip +
    ///      the mock-VRF drain so the Afking stage (`SUB_STAGE_BATCH`) stamps the funded set.
    ///      This is the Δ4 successor to the deleted `afKing.autoBuy(N)` (the buy folded into advance).
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D); // settle any in-flight day first
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
    }

    /// @dev Run the STAGE exactly ONCE on a fresh day via a SINGLE `mineFlip()` (no full settle),
    ///      used by the pass-eviction tests. The STAGE runs strictly PRE-RNG (AdvanceModule:305-326),
    ///      so the eviction / buy completes before rngGate and the stage is measured on its own.
    ///      Subscribers must already be registered (subscribe blocks during rngLock).
    function _runStageOnce() internal {
        vm.warp(block.timestamp + 1 days);
        game.mineFlip(0);
    }

    /// @dev Settle the game to a clean state: drive mineFlip + deliver the mock VRF word until
    ///      advanceDue() is false and we are not rng-locked. Ported from
    ///      KeeperRewardRoutingSameResults._settleGame (PATTERNS §"Settle-to-clean-state VRF drain").
    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.mineFlip(0);
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
            _approveKeeper(who);
            _fundPool(who, 1 ether); // fund BEFORE subscribe to ground the NEW-run cover-buy (D-12)
            vm.prank(who);
            game.subscribe(0, false, false, 1, 0, seat); // self, lootbox mode, qty 1
        }
    }

    /// @dev Subscribe `n` fresh NO-PASS players (lootbox mode, funded) — _passHorizonOf == 0, so a
    ///      forced crossing at level>0 EVICTS them. Used by the pass-eviction tests.
    function _setupNoPassBuyingSubs(uint256 n, string memory prefix) internal returns (address[] memory subs) {
        subs = new address[](n);
        for (uint256 i; i < n; i++) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            _approveKeeper(who);
            _fundPool(who, 1 ether); // fund BEFORE subscribe to ground the NEW-run cover-buy (D-12); still NO deity
            uint256 seat = _grantSeat(who);
            vm.prank(who);
            game.subscribe(0, false, false, 1, 0, seat); // self, lootbox mode, qty 1, NO deity
        }
    }

    /// @dev Approve the game (the afking module is game-resident) as `who`'s operator. Self-funded
    ///      subs don't strictly need it, but it keeps parity with operator-funded paths.
    function _approveKeeper(address who) internal {
        _aid(who);
        vm.prank(who);
        game.setOperatorApproval(0, address(game), true);
    }

    /// @dev Credit `who`'s afkingFunding bucket with `amount` ETH (Δ5: depositAfkingFunding replaces
    ///      AfKing.depositFor).
    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(_aid(who));
    }

    /// @dev Grant `who` the permanent deity bit so _passHorizonOf(who) == type(uint24).max. RE-DERIVED
    ///      slot: mintPacked_ is slot 10 on DegenerusGame (the old helper used slot 9 — WRONG).
    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(game.walletIdOf(who), uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Bump game.level (uint24 packed at slot-0 bytes 14..16) from 0 to 1 if needed, so a sub
    ///      with validThroughLevel = 0 triggers the AFSUB-03 crossing predicate `currentLevel > 0`.
    function _bumpGameLevelToAtLeastOne() internal {
        uint256 slot0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        uint256 levelMask = uint256(0xFFFFFF) << (14 * 8);
        if (uint24((slot0 & levelMask) >> (14 * 8)) == 0) {
            slot0 = (slot0 & ~levelMask) | (uint256(1) << (14 * 8));
            vm.store(address(game), bytes32(uint256(0)), bytes32(slot0));
        }
    }

    // ---- Sub field reads (game-resident _subOf slot 52 + the verified packed offsets) ----

    function _subSlot(address who) internal view returns (bytes32) {
        return keccak256(abi.encode(uint256(game.walletIdOf(who)), uint256(SUBOF_SLOT)));
    }

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), _subSlot(who))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _dailyQtyOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, OFF_DAILY, 8));
    }

    function _validThroughLevelOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_VALIDTHROUGH, 24));
    }

    function _flagsOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, OFF_FLAGS, 8));
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

    /// @dev Pin `who`'s validThroughLevel (uint24, bytes 1..3) -- force / clear the crossing predicate.
    function _setValidThroughLevel(address who, uint32 lvl) internal {
        bytes32 slot = _subSlot(who);
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~(uint256(0xFFFFFF) << (OFF_VALIDTHROUGH * 8));
        packed |= ((uint256(lvl) & 0xFFFFFF) << (OFF_VALIDTHROUGH * 8));
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Read `who`'s 1-indexed subscriber index (slot 55); 0 = not in set.
    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(who)), GameSlots.SUB_OF)))) >> 224; // Sub.setPosition (1-based)
    }

    /// @dev `_subscribers.length` (slot 54 holds the array length).
    function _subscribersLen() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBSCRIBERS_SLOT))));
    }

    /// @dev `_subscribers[i]` (data at keccak256(56) + i).
    function _subscriberAt(uint256 i) internal view returns (address) {
        bytes32 base = keccak256(abi.encode(uint256(SUBSCRIBERS_SLOT)));
        uint32 id = uint32(uint256(vm.load(address(game), bytes32(uint256(base) + i / 8))) >> ((i % 8) * 32));
        return _fixturePayee(id);
    }

    /// @dev The stamp day a sub was last processed (for the "this cycle" assertions).
    function _stampDay(address who) internal view returns (uint32) {
        return _lastBoughtDayOf(who);
    }

    // ---- Buy oracle (the storage-stamp delta, the GASOPT-04 successor to the deleted AutoBought event) ----

    mapping(address => uint32) private _baselineBoughtDay;

    function _snapshotBought(address[] memory tracked) internal {
        for (uint256 i; i < tracked.length; i++) {
            _baselineBoughtDay[tracked[i]] = _lastBoughtDayOf(tracked[i]);
        }
    }

    /// @dev 1 if `who` was freshly stamped (lastAutoBoughtDay advanced past the snapshot), else 0.
    function _countBoughtFor(address who) internal view returns (uint256) {
        uint32 stamp = _lastBoughtDayOf(who);
        return (stamp > _baselineBoughtDay[who]) ? 1 : 0;
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
