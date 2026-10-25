// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {QaSlots} from "../helpers/QaSlots.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title StreakSnapshotAndPendingFlipClampTest -- proves the single-integer streak path and the
///        saturating 16-bit checkpoint streak of the compact subscriber lane.
///
/// @notice Two properties, one fixture:
///   1. A manual quest streak carried into an afking run is snapshotted EXACTLY into the lane's 16-bit
///      checkpoint streak, including values above 255; the live streak is the checkpoint streak plus the
///      days from the checkpoint to the endpoint, and the finalize hands back exactly that.
///   2. The checkpoint streak SATURATES at `type(uint16).max`: a live `recordAfkingSecondary_g3316` bump and a
///      settlement that folds elapsed days in never wrap it to a small value. Settlement pays the derived
///      reward once, from the elapsed days, and a repeat claim finds nothing.
///
/// @dev The manual quest streak is driven by writing `questPlayerState[player].streak` (uint16, slot 1
///   off9) directly, the same dormant value `beginAfking` snapshots; day anchors are left so the decay
///   branch stays inert. Test-only: ZERO contracts/*.sol mutation.
contract StreakSnapshotAndPendingFlipClampTest is DeployProtocol {

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

    /// @dev Wallet IDs of `a`, registering any that hold none.
    function _aids(address[] memory a) internal returns (uint32[] memory ids) {
        ids = new uint32[](a.length);
        for (uint256 i; i < a.length; ++i) ids[i] = _aid(a[i]);
    }

    // -------------------------------------------------------------------------
    // questPlayerState (DegenerusQuests slot 1) field offsets within the packed slot
    // -------------------------------------------------------------------------
    /// @dev lastCompletedDay u24 off0, lastActiveDay u24 off3, lastSyncDay u24 off6, streak u16 off9,
    ///      baseStreak u16 off11, afkingActive bool off13.
    uint256 private constant QUESTSTATE_SLOT = QaSlots.STATE;
    uint256 private constant OFF_QS_SYNCDAY = 6;
    uint256 private constant OFF_QS_STREAK = 9;

    /// @dev recordAfkingSecondary_g3316 is QUESTS-gated; the live +1 bump is driven by pranking as this caller.
    address private constant QUESTS_CALLER = ContractAddresses.QUESTS;

    /// @dev The checkpoint streak saturates at type(uint16).max.
    uint256 private constant STREAK_LATCH_CEILING = 65_535;

    /// @dev QUEST_SLOT0_REWARD = 100 whole FLIP per credited day.
    uint256 private constant SLOT0_FLIP_PER_BUY = 100;

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;
    uint256 private _t; // explicit accumulating timestamp (the Foundry block.timestamp caching workaround)
    uint256 private _deliverNonce;
    DegenerusGameLens private lens;

    function setUp() public {
        _deployProtocol();
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
        lens = new DegenerusGameLens();
        _finishSubscriptionWindow();
    }

    // =========================================================================
    // Task 1 — pre-streak >255 snapshot exactness + the <=255 regression-safety + the saturation
    // =========================================================================

    /// @notice A manual quest streak ABOVE 255 carried into an afking run is snapshotted EXACTLY into the
    ///         16-bit checkpoint streak, the run reads the true base plus its credited days, and finalize
    ///         hands the streak back exactly.
    function test_PreStreakSnapshotExact_Above255() public {
        _assertSnapshotExact(makeAddr("snap_300"), 300);
        _assertSnapshotExact(makeAddr("snap_1000"), 1000);
        _assertSnapshotExact(makeAddr("snap_60000"), 60_000);
    }

    /// @notice For a carried-in streak <= 255 the snapshot/restore is exact too, including the old
    ///         8-bit boundary 255.
    function test_PreStreakSnapshotExact_AtOrBelow255() public {
        _assertSnapshotExact(makeAddr("snap_200"), 200);
        _assertSnapshotExact(makeAddr("snap_255"), 255);
        _assertSnapshotExact(makeAddr("snap_1"), 1);
    }

    /// @notice The checkpoint streak saturates at `type(uint16).max`. Driving it to the ceiling and then
    ///         exercising the live `recordAfkingSecondary_g3316` bump reads 65535 (saturated), never 0 (wrapped).
    function test_SecondaryBumpClampSaturatesAtUint16Max() public {
        address p = makeAddr("clamp_p");
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        uint32 pId = game.walletIdOf_g3120(p);
        assertGt(_positionOf(p), 0, "non-vacuity: a live run grounds the bump path");

        _setCheckpointStreak(p, STREAK_LATCH_CEILING);
        assertEq(_checkpointStreakOf(p), STREAK_LATCH_CEILING, "streak pinned at the uint16 ceiling");
        vm.prank(QUESTS_CALLER);
        game.recordAfkingSecondary_g3316(pId, 1);
        assertEq(_checkpointStreakOf(p), STREAK_LATCH_CEILING, "+1 at the ceiling stays 65535 (saturates, never wraps to 0)");

        _setCheckpointStreak(p, STREAK_LATCH_CEILING - 1);
        vm.prank(QUESTS_CALLER);
        game.recordAfkingSecondary_g3316(pId, 1);
        assertEq(_checkpointStreakOf(p), STREAK_LATCH_CEILING, "a +1 from one-below reaches exactly the ceiling");

        _setCheckpointStreak(p, 255);
        vm.prank(QUESTS_CALLER);
        game.recordAfkingSecondary_g3316(pId, 1);
        assertEq(_checkpointStreakOf(p), 256, "a +1 from 255 reads 256 (past the old 8-bit ceiling)");

        // amount > 1 (the level-quest path): the full amount is added, then the clamp binds at the ceiling.
        _setCheckpointStreak(p, 250);
        vm.prank(QUESTS_CALLER);
        game.recordAfkingSecondary_g3316(pId, 5);
        assertEq(_checkpointStreakOf(p), 255, "a +5 from 250 reaches 255 (full amount applied)");

        _setCheckpointStreak(p, STREAK_LATCH_CEILING - 3);
        vm.prank(QUESTS_CALLER);
        game.recordAfkingSecondary_g3316(pId, 5);
        assertEq(_checkpointStreakOf(p), STREAK_LATCH_CEILING, "a +5 overshooting the ceiling saturates at 65535");
    }

    /// @notice The bump moves only the streak: the checkpoint day, and so the owed rewards, stay put.
    function test_SecondaryBumpAndFoilFloorKeepTheCheckpoint() public {
        address p = makeAddr("floor_p");
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        _deliverDay(_singleton(p), 0xF100);
        uint32 pId = game.walletIdOf_g3120(p);
        DegenerusGameLens.SubFull memory before = lens.subInfoFullById(address(game), pId);
        assertEq(before.effectiveStreak, 1, "one credited day on a zero base");

        vm.prank(QUESTS_CALLER);
        game.recordAfkingSecondary_g3316(pId, 1);
        DegenerusGameLens.SubFull memory bumped = lens.subInfoFullById(address(game), pId);
        assertEq(bumped.effectiveStreak, 2, "the bump adds to the live streak");
        assertEq(bumped.checkpointDay, before.checkpointDay, "the checkpoint day does not move");
        assertEq(bumped.owedFlip, before.owedFlip, "nothing owed changes");

        vm.prank(QUESTS_CALLER);
        game.floorAfkingStreakBase(pId, 12);
        DegenerusGameLens.SubFull memory floored = lens.subInfoFullById(address(game), pId);
        assertEq(floored.effectiveStreak, 12, "the live streak is raised to the floor, like a manual player's");
        assertEq(floored.checkpointDay, before.checkpointDay, "the checkpoint day does not move");
        vm.prank(QUESTS_CALLER);
        game.floorAfkingStreakBase(pId, 12);
        assertEq(lens.subInfoFullById(address(game), pId).effectiveStreak, 12, "a floor already met changes nothing");
    }

    /// @dev Drive `who`'s manual quest streak to `streakValue`, begin an afking run, and assert (1) the
    ///      checkpoint streak is EXACTLY `streakValue` (no truncation) and (2) the finalize hands back the
    ///      derived live streak EXACTLY, never a floor-hacked or truncated value.
    function _assertSnapshotExact(address who, uint16 streakValue) internal {
        _setManualQuestStreak(who, streakValue);
        _fundPool(who, 50 ether);

        _subscribeLootbox(who, 1);
        assertEq(
            _checkpointStreakOf(who),
            streakValue,
            "run-start: the checkpoint streak snapshots the carried-in manual streak EXACTLY"
        );

        // Deliver a day; the snapshot stays, and the live streak adds the credited day.
        _deliverDay(_singleton(who), uint256(keccak256(abi.encode("snap_dd", who))) | 1);
        assertEq(_checkpointStreakOf(who), streakValue, "mid-run: the checkpoint streak is unchanged until settlement");
        uint256 earned = lens.subInfoFullById(address(game), game.walletIdOf_g3120(who)).effectiveStreak;
        assertEq(earned, uint256(streakValue) + 1, "the live streak is the snapshot plus the credited day");

        // Finalize via explicit cancel: the manual streak is handed back EXACTLY the earned value.
        vm.prank(who);
        game.subscribe(0, false, 0, 0); // explicit cancel -> finalizeAfking
        assertEq(
            _manualStreakOf(who),
            earned,
            "finalize: the manual quest streak is handed back EXACTLY the earned run streak"
        );
    }

    // =========================================================================
    // Task 2 — settlement from elapsed days: pays once, saturates, never wraps
    // =========================================================================

    /// @notice Settlement pays exactly the elapsed days' reward once and a repeat claim finds nothing.
    function test_SettlementPaysElapsedDaysOnce() public {
        address p = makeAddr("settle_p");
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        _deliverDay(_singleton(p), 0xC1AAA1);
        _deliverDay(_singleton(p), 0xC1AAA2);
        DegenerusGameLens.SubFull memory owed = lens.subInfoFullById(address(game), game.walletIdOf_g3120(p));
        assertEq(owed.owedFlip, 2 * SLOT0_FLIP_PER_BUY, "two elapsed days are owed");

        vm.recordLogs();
        game.claimAfkingFlip(_aids(_singleton(p)));
        assertEq(_flipClaimed(p), 2 * SLOT0_FLIP_PER_BUY, "settle pays exactly the elapsed days");
        assertEq(lens.subInfoFullById(address(game), game.walletIdOf_g3120(p)).owedFlip, 0, "nothing left owed");
        vm.recordLogs();
        game.claimAfkingFlip(_aids(_singleton(p)));
        assertEq(_flipClaimed(p), 0, "a re-claim finds 0");
    }

    /// @notice Folding elapsed days into a checkpoint streak already at the ceiling saturates it, and the
    ///         live streak read afterwards does not wrap.
    function test_SettlementSaturatesCheckpointStreak() public {
        address p = makeAddr("sat_p");
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        _setCheckpointStreak(p, STREAK_LATCH_CEILING - 1);
        _deliverDay(_singleton(p), 0xC1AAA3);
        _deliverDay(_singleton(p), 0xC1AAA4);
        _deliverDay(_singleton(p), 0xC1AAA5);
        game.claimAfkingFlip(_aids(_singleton(p)));
        assertEq(_checkpointStreakOf(p), STREAK_LATCH_CEILING, "three folded days saturate at 65535, never wrap");
        assertGe(lens.subInfoFullById(address(game), game.walletIdOf_g3120(p)).effectiveStreak, STREAK_LATCH_CEILING);
    }

    // =========================================================================
    // Lane writers/readers + manual-streak drive
    // =========================================================================

    function _positionOf(address who) internal view returns (uint256 position1) {
        (, position1) = GameSlotKeys.subLane(address(game), game.walletIdOf_g3120(who));
    }

    function _checkpointStreakOf(address who) internal view returns (uint256) {
        (uint256 lane,) = GameSlotKeys.subLane(address(game), game.walletIdOf_g3120(who));
        return (lane >> 69) & 0xffff;
    }

    /// @dev Write the 16-bit checkpoint streak (lane bits 69-84) directly, leaving the rest of the word intact.
    function _setCheckpointStreak(address who, uint256 value) internal {
        (, uint256 position1) = GameSlotKeys.subLane(address(game), game.walletIdOf_g3120(who));
        require(position1 != 0, "not a member");
        uint256 position = position1 - 1;
        bytes32 slot = bytes32(uint256(keccak256(abi.encode(GameSlots.SUBSCRIBERS))) + position / 3);
        uint256 shift = (position % 3) * 85 + 69;
        uint256 word = uint256(vm.load(address(game), slot));
        word = (word & ~(uint256(0xffff) << shift)) | ((value & 0xffff) << shift);
        vm.store(address(game), slot, bytes32(word));
    }

    /// @dev Whole FLIP the AfkingFlipClaimed events recorded since the last vm.recordLogs() paid `who`.
    function _flipClaimed(address who) internal returns (uint256 total) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("AfkingFlipClaimed(uint32,uint256)");
        uint32 id = game.walletIdOf_g3120(who);
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2 || logs[i].topics[0] != sig) continue;
            if (uint32(uint256(logs[i].topics[1])) != id) continue;
            total += abi.decode(logs[i].data, (uint256));
        }
    }

    /// @dev The manual quest streak handed back to `who` after finalize.
    function _manualStreakOf(address who) internal view returns (uint256 streak) {
        (streak, ) = quests.effectiveBaseStreakAndAfking_g1521(game.walletIdOf_g3120(who), _fixtureGameDay());
    }

    /// @dev Drive `player`'s dormant manual quest streak to `q` by writing `questPlayerState[player]` directly:
    ///      `state.streak = q` with `lastSyncDay` non-zero and the day anchors 0, so `_questSyncState` skips its
    ///      decay branch and `beginAfking` snapshots `q` verbatim.
    function _setManualQuestStreak(address player, uint16 q) internal {
        uint32 id = game.walletIdOf_g3120(player);
        if (id == 0) id = _giveWalletId(player);
        bytes32 slot = keccak256(abi.encode(uint256(id), QUESTSTATE_SLOT));
        uint256 word = (uint256(q) << (OFF_QS_STREAK * 8)) | (uint256(1) << (OFF_QS_SYNCDAY * 8));
        vm.store(address(quests), slot, bytes32(word));
    }

    // =========================================================================
    // Afking-run drive helpers (ported from V56SecUnmanipulable, re-pointed to the post-PACK Sub offsets)
    // =========================================================================

    /// @dev Deliver ONE funded day to `who`: a new-day pass buy (stamps the box and
    ///      moves the endpoint), settle clean, then open the pending box so the no-orphan guard
    ///      does not skip the next day's buy. Each delivered day moves the endpoint one day.
    function _deliverDay(address[] memory who, uint256 vrfWord) internal {
        uint256 w = uint256(keccak256(abi.encode("dlv", vrfWord, _deliverNonce++))) | 1;
        _runStageNewDay(w);
        _settleClean(uint256(keccak256(abi.encode("dlvc", w))) | 1);
        vm.startPrank(makeAddr("deliver_opener"));
        _mineAll(64);
        vm.stopPrank();
        who;
    }

    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        _t += 1 days;
        vm.warp(_t);
        _settleGame(vrfWord);
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.mineRun(0);
            _fulfillPending(vrfWord);
        }
    }

    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.mineRun(0);
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

    function _subscribeLootbox(address who, uint8 q) internal {
        uint256 seat = _grantSeat(who); // the AFKing Subscription Token is the subscribe credential (a new run burns one seat)
        vm.prank(who);
        game.subscribe(0, false, q, seat); // self, lootbox mode, no reinvest
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(_aid(who));
    }

    function _singleton(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }
}
