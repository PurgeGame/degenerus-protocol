// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @title StreakSnapshotAndPendingFlipClampTest -- proves the v69 single-integer streak path and the
///        narrowed `pendingFlip` saturating clamp against the post-PACK Sub accumulator.
///
/// @notice Two properties, one fixture:
///   1. The afking-run streak latch is uint16: a manual quest streak carried into an afking run is
///      snapshotted EXACTLY into the latch, including values above 255 — the old uint8/255 truncation and
///      the `finalizeAfking` floor-hack restore are gone. A streak <= 255 is byte-identical to before. The
///      `_setStreakBase` clamp is KEPT, re-pinned to `type(uint16).max`, so the live `recordAfkingSecondary`
///      +1 bump saturates at 65535 instead of wrapping 65536 -> 0.
///   2. `pendingFlip` is uint24 with a saturating clamp at `type(uint24).max = 16_777_215` whole FLIP. The
///      clamp `min(newOwed, type(uint24).max)` PRECEDES the `uint24(...)` cast, so the cast is lossless by
///      construction: at/over the ceiling the field reads exactly 16_777_215, never a wrapped small value.
///
/// @dev Reuses the afking-run drive ported from V56SecUnmanipulable, RE-POINTED to the post-PACK Sub
///   accumulator (affiliateBase u32 off23, pendingFlip u24 off27, subStreakLatch u16 off30 — re-derived from
///   the v69 storageLayout, NOT the stale pre-PACK V56 offsets which read pendingFlip u32 off27 /
///   subStreakLatch u8 off31). The manual quest streak is driven by writing `questPlayerState[player].streak`
///   (uint16, slot 1 off9) directly, the same dormant value `beginAfking` snapshots; day anchors are left so
///   the decay branch stays inert. Test-only: ZERO contracts/*.sol mutation.
contract StreakSnapshotAndPendingFlipClampTest is DeployProtocol {
    // -------------------------------------------------------------------------
    // questPlayerState (DegenerusQuests slot 1) field offsets within the packed slot
    // -------------------------------------------------------------------------
    /// @dev lastCompletedDay u24 off0, lastActiveDay u24 off3, lastSyncDay u24 off6, streak u16 off9,
    ///      baseStreak u16 off11, afkingActive bool off13.
    uint256 private constant QUESTSTATE_SLOT = 1;
    uint256 private constant OFF_QS_SYNCDAY = 6;
    uint256 private constant OFF_QS_STREAK = 9;

    // -------------------------------------------------------------------------
    // Game-resident slots + the POST-PACK Sub accumulator offsets (re-derived from the v69 storageLayout)
    // -------------------------------------------------------------------------
    /// @dev _subOf mapping root @ slot 54; mintPacked_ deity bit @ bit 184. The repacked accumulator section
    ///      is affiliateBase u32 off23, pendingFlip u24 off27, subStreakLatch u16 off30 (latch widened 8->16,
    ///      pendingFlip narrowed 32->24). The afking day markers: afkCoveredThroughDay u24 off17,
    ///      afkingStartDay u24 off20.
    uint256 private constant SUBOF_SLOT = 53;
    uint256 private constant MINTPACKED_SLOT = 9;
    uint256 private constant DEITY_SHIFT = 184;
    uint256 private constant OFF_AFKCOVERED = 16;
    uint256 private constant OFF_AFKINGSTART = 19;
    uint256 private constant OFF_PENDINGFLIP = 26; // uint24 pendingFlip (bytes 27..29)
    uint256 private constant OFF_STREAKLATCH = 29; // uint16 subStreakLatch (bytes 30..31)

    /// @dev recordAfkingSecondary is QUESTS-gated; the live +1 bump is driven by pranking as this caller.
    address private constant QUESTS_CALLER = address(0x3Cff5E7eBecb676c3Cb602D0ef2d46710b88854E);

    /// @dev The shipped ceilings: pendingFlip saturates at type(uint24).max; the streak latch clamp at
    ///      type(uint16).max.
    uint256 private constant PENDINGFLIP_CEILING = 16_777_215; // type(uint24).max
    uint256 private constant STREAK_LATCH_CEILING = 65_535; // type(uint16).max

    /// @dev QUEST_SLOT0_REWARD / 1 ether = 100 whole FLIP accrued to pendingFlip per delivered buy.
    uint256 private constant SLOT0_FLIP_PER_BUY = 100;

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;
    uint256 private _t; // explicit accumulating timestamp (the Foundry block.timestamp caching workaround)
    uint256 private _deliverNonce;

    function setUp() public {
        _deployProtocol();
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
    }

    // =========================================================================
    // Task 1 — pre-streak >255 snapshot exactness + the <=255 regression-safety + the latch clamp
    // =========================================================================

    /// @notice A manual quest streak ABOVE 255 carried into an afking run is snapshotted EXACTLY into the
    ///         widened uint16 latch, the run reads the true >255 base, and finalize hands the manual streak
    ///         back exactly. Fails-without: under the old uint8/255 path the latch would have truncated to 255
    ///         and the finalize floor-hack would have restored 255 — both arms assert the TRUE value, so the
    ///         old truncation regression would fail here.
    function test_PreStreakSnapshotExact_Above255() public {
        _assertSnapshotExact(makeAddr("snap_300"), 300);
        _assertSnapshotExact(makeAddr("snap_1000"), 1000);
        // A value above the old uint8 ceiling but well under the uint16 ceiling — the widened latch holds it
        // verbatim; the old path would have clamped this to 255.
        _assertSnapshotExact(makeAddr("snap_60000"), 60_000);
    }

    /// @notice For a carried-in streak <= 255 the snapshot/restore is byte-identical to before — the clamp
    ///         never bound for these, so the widening is regression-safe. Includes the old-ceiling boundary 255.
    function test_PreStreakSnapshotByteIdentical_AtOrBelow255() public {
        _assertSnapshotExact(makeAddr("snap_200"), 200);
        _assertSnapshotExact(makeAddr("snap_255"), 255); // the old uint8 ceiling boundary — still exact
        _assertSnapshotExact(makeAddr("snap_1"), 1);
    }

    /// @notice The KEPT `_setStreakBase` clamp saturates at `type(uint16).max`. Driving the latch to the
    ///         ceiling and then exercising the live `recordAfkingSecondary` +1 bump reads 65535 (saturated),
    ///         never 0 (wrapped 65536 -> 0). The clamp guards the bump from wrapping the field at the ceiling.
    function test_SetStreakBaseClampSaturatesAtUint16Max() public {
        address p = makeAddr("clamp_p");
        _grantDeityPass(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1);
        // Ground a live run so afkingStartDay != 0 and recordAfkingSecondary is not a no-op.
        _deliverDay(_singleton(p), 0xC1A11);
        assertGt(_afkingStartOf(p), 0, "non-vacuity: a live afking run grounds the +1 bump path");

        // Pin the latch AT the ceiling, then bump +1 through the live secondary path: the kept clamp
        // saturates the write at 65535 (newOwed = 65536 > type(uint16).max -> 65535), never wrapping to 0.
        _setStreakLatchSlot(p, STREAK_LATCH_CEILING);
        assertEq(_streakLatch16Of(p), STREAK_LATCH_CEILING, "latch pinned at the uint16 ceiling");
        vm.prank(QUESTS_CALLER);
        game.recordAfkingSecondary(p, 1); // +1 at the ceiling -> clamp saturates
        assertEq(_streakLatch16Of(p), STREAK_LATCH_CEILING, "clamp: +1 at the ceiling stays 65535 (saturates, never wraps to 0)");
        assertTrue(_streakLatch16Of(p) != 0, "clamp: the +1 bump did NOT wrap the latch to 0");

        // One below the ceiling: the same +1 bump advances normally to the ceiling (the clamp only binds at
        // the top), so the saturation is a true clamp, not a stuck value.
        _setStreakLatchSlot(p, STREAK_LATCH_CEILING - 1);
        vm.prank(QUESTS_CALLER);
        game.recordAfkingSecondary(p, 1);
        assertEq(_streakLatch16Of(p), STREAK_LATCH_CEILING, "clamp: a +1 from one-below reaches exactly the ceiling");

        // A value below 255 (the old uint8 ceiling) bumps cleanly into the >255 range — the widened latch
        // carries it past the old truncation point, so the +1 path is not the only thing wider; the base is too.
        _setStreakLatchSlot(p, 255);
        vm.prank(QUESTS_CALLER);
        game.recordAfkingSecondary(p, 1);
        assertEq(_streakLatch16Of(p), 256, "clamp/widen: a +1 from 255 reads 256 (the latch carries past the old uint8 ceiling)");

        // amount > 1 (the level-quest path, LEVEL_QUEST_STREAK_BONUS = 5): the full amount is added,
        // then the same clamp binds at the ceiling. A +5 from a non-ceiling value advances by 5.
        _setStreakLatchSlot(p, 250);
        vm.prank(QUESTS_CALLER);
        game.recordAfkingSecondary(p, 5);
        assertEq(_streakLatch16Of(p), 255, "amount: a +5 from 250 reaches 255 (full amount applied)");

        // A +5 that would overshoot the ceiling saturates to 65535, never wrapping past it.
        _setStreakLatchSlot(p, STREAK_LATCH_CEILING - 3);
        vm.prank(QUESTS_CALLER);
        game.recordAfkingSecondary(p, 5);
        assertEq(_streakLatch16Of(p), STREAK_LATCH_CEILING, "amount: a +5 overshooting the ceiling saturates at 65535");
        assertTrue(_streakLatch16Of(p) != 0, "amount: the +5 overshoot did NOT wrap the latch to 0");
    }

    /// @dev Drive `who`'s manual quest streak to `streakValue`, begin an afking run, and assert (1) the
    ///      run-start latch snapshot is EXACTLY `streakValue` (no uint8/255 truncation) and (2) the finalize
    ///      hands back the earned run streak EXACTLY — the live `base + funded-delivered-days` read just before
    ///      cancel, never a floor-hacked or truncated value. For a >255 base the earned streak stays >255,
    ///      proving the carried-in value survives both the snapshot and the finalize past the old uint8 ceiling.
    function _assertSnapshotExact(address who, uint16 streakValue) internal {
        _setManualQuestStreak(who, streakValue);
        _grantDeityPass(who);
        _fundPool(who, 50 ether);

        // Subscribe grounds the run: beginAfking snapshots state.streak (uint16) and _setStreakBase writes it
        // into the latch. The run base must equal the carried-in manual streak EXACTLY (>255 is NOT truncated
        // to 255 as the old uint8 latch would have).
        _subscribeLootbox(who, 1);
        assertEq(
            _streakLatch16Of(who),
            streakValue,
            "run-start: the uint16 latch snapshots the carried-in manual streak EXACTLY (old uint8/255 path would read 255)"
        );

        // Deliver a day so the run is live; the latch base is unchanged (the run advances the covered span,
        // not the snapshot), so the mid-run base still reads the true >255 value.
        _deliverDay(_singleton(who), uint256(keccak256(abi.encode("snap_dd", who))) | 1);
        assertEq(_streakLatch16Of(who), streakValue, "mid-run: the latch base still reads the true carried-in streak");

        // The live earned run streak (base + funded delivered days) read while the run is live, no decay. For a
        // >255 base this is itself >255 — the old uint8 latch could not have represented it at all.
        uint256 earned = _liveAfkingStreakOf(who);
        assertGe(earned, streakValue, "the earned run streak includes the carried-in base (>= the snapshot)");

        // Finalize via explicit cancel: with a fresh delivered day (covered + 1 >= currentDay) the funding-kill
        // decay guard keeps the earned streak, and the earned streak rides the carried-in snapshot. The manual
        // state.streak is handed back EXACTLY the earned value — no floor-hack restore, no uint8 truncation.
        vm.prank(who);
        game.subscribe(address(0), false, false, 0, address(0)); // explicit cancel -> finalizeAfking
        assertEq(
            _manualStreakOf(who),
            earned,
            "finalize: the manual quest streak is handed back EXACTLY the earned run streak (no floor-hack, no truncation)"
        );
    }

    /// @dev The live afking compute-on-read streak `_streakBaseOf + (covered - afkingStartDay)` while the last
    ///      covered day is no older than yesterday, else 0 (decay-on-read) — mirrors `_afkingStreak` off the
    ///      post-PACK Sub slot so the finalize hand-back is checked against the same value the contract earns.
    function _liveAfkingStreakOf(address who) internal view returns (uint256) {
        uint256 covered = _afkCoveredOf(who);
        uint256 today = game.currentDayView();
        if (today == 0 || covered + 1 < today) return 0;
        return _streakLatch16Of(who) + covered - _afkingStartOf(who);
    }

    function _afkCoveredOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_AFKCOVERED, 24));
    }

    // =========================================================================
    // Task 2 — the pendingFlip uint24 saturating clamp (clamps, never wraps)
    // =========================================================================

    /// @notice `pendingFlip` saturates at exactly `type(uint24).max = 16_777_215`. Three cases:
    ///         (a) one-below the ceiling, an accrue crossing it clamps to the ceiling; (b) AT the ceiling, an
    ///         accrue stays at the ceiling; (c) over-ceiling, the read is the ceiling and explicitly NOT the
    ///         wrap value `k = (ceiling + reward) mod 2^24`, so a wrap-to-small-value regression fails.
    function test_PendingFlipSaturatesAtUint24Ceiling() public {
        // (a) one-below: pre-load 16_777_214, accrue the slot-0 reward (100) which crosses the ceiling ->
        //     clamps to exactly 16_777_215 (NOT 16_777_214 + 100 = 16_777_314, which exceeds uint24).
        address a = makeAddr("clamp_below");
        _armLiveSub(a);
        _setPendingFlipSlot(a, PENDINGFLIP_CEILING - 1);
        _deliverDay(_singleton(a), 0xC1AAA1); // on-chain accrue + clamp executes against the near-ceiling total
        assertEq(_pendingFlip24Of(a), PENDINGFLIP_CEILING, "(a) one-below + accrue clamps to exactly the uint24 ceiling");

        // (b) at-ceiling: pre-load 16_777_215, accrue -> stays at the ceiling (no wrap).
        address b = makeAddr("clamp_at");
        _armLiveSub(b);
        _setPendingFlipSlot(b, PENDINGFLIP_CEILING);
        _deliverDay(_singleton(b), 0xC1AAA2);
        assertEq(_pendingFlip24Of(b), PENDINGFLIP_CEILING, "(b) at-ceiling + accrue stays at the ceiling (no wrap)");

        // (c) over-ceiling: pick a pre-load so newOwed = ceiling + k for a known k. With the slot-0 reward of
        //     100 whole FLIP, pre-loading `ceiling - 50` gives newOwed = ceiling + 50, so the wrap value would
        //     be k = 49 (newOwed mod 2^24 = (ceiling + 50) - 2^24 = 49, since ceiling = 2^24 - 1). The field
        //     must read the ceiling and explicitly NOT 49.
        address c = makeAddr("clamp_over");
        _armLiveSub(c);
        uint256 preload = PENDINGFLIP_CEILING - 50;
        _setPendingFlipSlot(c, preload);
        _deliverDay(_singleton(c), 0xC1AAA3);
        uint256 wrapValue = (preload + SLOT0_FLIP_PER_BUY) % (uint256(1) << 24); // (ceiling + 50) mod 2^24 = 49
        assertEq(wrapValue, 49, "non-vacuity: the would-be wrap value is the small 49, not the ceiling");
        assertEq(_pendingFlip24Of(c), PENDINGFLIP_CEILING, "(c) over-ceiling reads exactly the uint24 ceiling");
        assertTrue(_pendingFlip24Of(c) != wrapValue, "(c) the field did NOT wrap to the small value k (clamp precedes the cast -> lossless)");
    }

    /// @notice A settle/claim of a pendingFlip pinned at the ceiling reads the clamped value back as a uint256,
    ///         credits exactly 16_777_215 whole FLIP (x 1e18), and zeroes the field — the clamp did not corrupt
    ///         the claimed amount, and `affiliateBase` is untouched.
    function test_PendingFlipSettleRoundTripUnderClamp() public {
        address p = makeAddr("settle_p");
        _armLiveSub(p);
        uint256 affBefore = _affiliateBase32Of(p);

        // Pin pendingFlip at the ceiling, then drive the player-pull claim/settle path.
        _setPendingFlipSlot(p, PENDINGFLIP_CEILING);
        assertEq(_pendingFlip24Of(p), PENDINGFLIP_CEILING, "non-vacuity: pendingFlip pinned at the ceiling");

        uint256 stakeBefore = coinflip.coinflipAmount(p);
        game.claimAfkingFlip(_singleton(p)); // _settlePendingFlip: reads owed as uint256, zeroes the field, credits
        uint256 stakeAfter = coinflip.coinflipAmount(p);

        assertEq(stakeAfter - stakeBefore, PENDINGFLIP_CEILING * 1 ether, "settle credits exactly the clamped 16,777,215 whole FLIP (x 1e18)");
        assertEq(_pendingFlip24Of(p), 0, "settle zeroes pendingFlip (a re-claim finds 0)");
        assertEq(_affiliateBase32Of(p), affBefore, "settle/clamp leaves affiliateBase untouched (its own clamp is out of scope)");
    }

    /// @dev Arm a deity-passed, funded, live sub for `who` (subscribe + deliver one day) so the on-chain accrue
    ///      + clamp path runs against a pre-loaded near-ceiling pendingFlip.
    function _armLiveSub(address who) internal {
        _grantDeityPass(who);
        _fundPool(who, 50 ether);
        _subscribeLootbox(who, 1);
    }

    // =========================================================================
    // Sub-slot writers/readers (POST-PACK offsets) + manual-streak drive
    // =========================================================================

    /// @dev Write the uint16 streak latch (off 30) directly, leaving the rest of the slot intact.
    function _setStreakLatchSlot(address who, uint256 value) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~(uint256(0xFFFF) << (OFF_STREAKLATCH * 8));
        packed |= (value & 0xFFFF) << (OFF_STREAKLATCH * 8);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Write the uint24 pendingFlip (off 27) directly, leaving the rest of the slot intact.
    function _setPendingFlipSlot(address who, uint256 value) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed &= ~(uint256(0xFFFFFF) << (OFF_PENDINGFLIP * 8));
        packed |= (value & 0xFFFFFF) << (OFF_PENDINGFLIP * 8);
        vm.store(address(game), slot, bytes32(packed));
    }

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    /// @dev The afking-run streak base — the FULL post-PACK uint16 latch (off 30, width 16).
    function _streakLatch16Of(address who) internal view returns (uint256) {
        return _subField(who, OFF_STREAKLATCH, 16);
    }

    /// @dev pendingFlip — the post-PACK uint24 accumulator (off 27, width 24), NOT the V56 width-32 reader.
    function _pendingFlip24Of(address who) internal view returns (uint256) {
        return _subField(who, OFF_PENDINGFLIP, 24);
    }

    function _affiliateBase32Of(address who) internal view returns (uint256) {
        return _subField(who, 22, 32);
    }

    function _afkingStartOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_AFKINGSTART, 24));
    }

    /// @dev The manual quest streak handed back to `who` after finalize — the protocol's own quest-streak
    ///      source (the dormant value the score reads for a non-afker).
    function _manualStreakOf(address who) internal view returns (uint256 streak) {
        (streak, ) = quests.effectiveBaseStreakAndAfking(who);
    }

    /// @dev Drive `player`'s dormant manual quest streak to `q` by writing `questPlayerState[player]` directly:
    ///      `state.streak = q` with `lastSyncDay` non-zero and the day anchors 0, so `_questSyncState` skips its
    ///      decay branch and `beginAfking` snapshots `q` verbatim.
    function _setManualQuestStreak(address player, uint16 q) internal {
        bytes32 slot = keccak256(abi.encode(player, QUESTSTATE_SLOT));
        uint256 word = (uint256(q) << (OFF_QS_STREAK * 8)) | (uint256(1) << (OFF_QS_SYNCDAY * 8));
        vm.store(address(quests), slot, bytes32(word));
    }

    // =========================================================================
    // Afking-run drive helpers (ported from V56SecUnmanipulable, re-pointed to the post-PACK Sub offsets)
    // =========================================================================

    /// @dev Deliver ONE funded day to `who`: a new-day STAGE buy (stamps the box + accrues pendingFlip +
    ///      advances the covered high-water), settle clean, then open the pending box so the no-orphan guard
    ///      does not skip the next day's buy. Each delivered day runs the on-chain accrue + uint24 clamp.
    function _deliverDay(address[] memory who, uint256 vrfWord) internal {
        uint256 w = uint256(keccak256(abi.encode("dlv", vrfWord, _deliverNonce++))) | 1;
        _runStageNewDay(w);
        _settleClean(uint256(keccak256(abi.encode("dlvc", w))) | 1);
        vm.prank(makeAddr("deliver_opener"));
        game.openBoxes(400);
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

    function _subscribeLootbox(address who, uint8 q) internal {
        vm.prank(who);
        game.subscribe(address(0), false, false, q, address(0)); // self, lootbox mode, no reinvest
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        vm.store(address(game), slot, bytes32(packed | (uint256(1) << DEITY_SHIFT)));
    }

    function _singleton(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }
}
