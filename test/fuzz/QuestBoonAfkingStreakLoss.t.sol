// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title QuestBoonAfkingStreakLossTest -- reproduces the activity-boon streak-award value-loss + orphaned
///        century-shield defect when the recipient has a LIVE afking run.
///
/// @notice The activity boon (lootbox open path, including an afking auto-open) routes through
///         DegenerusGameBoonModule.consumeActivityBoon, which runs in the GAME storage context (delegatecall)
///         and calls `quests.awardQuestStreakBonus(player, bonus, currentDay)` (DegenerusQuests.sol:439).
///         `awardQuestStreakBonus` is `onlyGame`; the faithful reachable reproduction is therefore a direct
///         `vm.prank(ContractAddresses.GAME)` call into `quests.awardQuestStreakBonus(...)` with the player
///         holding a live afking run -- byte-identical to the call the boon module makes.
///
/// @notice While afking, the manual `state.streak` is DORMANT: `finalizeAfking` (DegenerusQuests.sol:586)
///         overwrites it with the afking-computed `earnedStreak` (the afking "sub streak base" plus funded
///         delivered days, owned Game-side via GameAfkingModule). `awardQuestStreakBonus` (CURRENT code) bumps
///         the dormant `state.streak` and grants a century shield off it. This test proves two failures:
///         (a) the bonus does NOT reach the afking sub streak base (the value that actually pays the afker) --
///             so it is DISCARDED at finalize (value loss); AND
///         (b) the century shield it grants off the transient streak SURVIVES finalize as an orphan, while the
///             finalized earned streak is below that century -- a double-credit hazard (the same century can be
///             shield-granted again on a genuine later re-climb, because `_grantCenturyShield` re-arms the
///             high-water DOWN when the streak drops at finalize).
///
/// @dev Every OTHER quest-streak source already routes the bump into the afking sub streak base while afking
///      (daily secondary `recordAfkingSecondary(player,1)`; level-quest `recordAfkingSecondary(player,5)`; foil
///      floor `floorAfkingStreakBase(...)`). `awardQuestStreakBonus` is the only source missing this routing.
///
///      Fixture reuse: the afking-run drive (deity grant, funding, lootbox subscribe, day delivery, sub-slot
///      offsets) is ported from StreakSnapshotAndPendingFlipClamp.t.sol, RE-POINTED to the same post-PACK Sub
///      accumulator offsets. The afking sub streak base is the uint16 `subStreakLatch` (off 30). The manual
///      quest streak / shield are read from `questPlayerState` (DegenerusQuests slot 1) packed fields.
///      Test-only: ZERO contracts/*.sol mutation in this file.
contract QuestBoonAfkingStreakLossTest is DeployProtocol {
    // -------------------------------------------------------------------------
    // questPlayerState (DegenerusQuests slot 1) packed-field byte offsets
    // -------------------------------------------------------------------------
    /// @dev lastCompletedDay u24 off0, lastActiveDay u24 off3, lastSyncDay u24 off6, streak u16 off9,
    ///      baseStreak u16 off11, afkingActive bool off13, ..., completionMask u8 off24, streakShield u8 off25,
    ///      shieldCenturyHighWater u8 off26 (PlayerQuestState single-slot pack, DegenerusQuests.sol:288).
    uint256 private constant QUESTSTATE_SLOT = 1;
    uint256 private constant OFF_QS_SYNCDAY = 6; // uint24 lastSyncDay
    uint256 private constant OFF_QS_STREAK = 9; // uint16 streak
    uint256 private constant OFF_QS_SHIELD = 25; // uint8 streakShield
    uint256 private constant OFF_QS_HIGHWATER = 26; // uint8 shieldCenturyHighWater

    // -------------------------------------------------------------------------
    // Game-resident _subOf accumulator (post-PACK offsets, re-derived from the v69 storageLayout)
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = 54;
    uint256 private constant MINTPACKED_SLOT = 9;
    uint256 private constant DEITY_SHIFT = 184;
    uint256 private constant OFF_AFKINGSTART = 20; // uint24 afkingStartDay
    uint256 private constant OFF_STREAKLATCH = 30; // uint16 subStreakLatch (the afking sub streak base)

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;
    uint256 private _t;
    uint256 private _deliverNonce;

    function setUp() public {
        _deployProtocol();
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
    }

    // =========================================================================
    // The repro: activity-boon streak award during a live afking run
    // =========================================================================

    /// @notice With a player mid afking-run, the activity-boon streak award (`awardQuestStreakBonus` called as
    ///         GAME, exactly as the boon module reaches it) is supposed to credit the player's reward streak and
    ///         grant a century shield once. CURRENT code instead writes the dormant manual `state.streak` (which
    ///         `finalizeAfking` overwrites) and grants a century shield off it:
    ///           (a) the afking sub streak base -- the value that actually pays the afker -- is UNCHANGED, so the
    ///               bonus is discarded at finalize (value loss); AND
    ///           (b) the granted century shield SURVIVES finalize as an orphan while the finalized earned streak
    ///               is below that century (a re-grantable double-credit).
    ///         The FIXED code routes the bonus into the afking sub streak base (recordAfkingSecondary), so the
    ///         base rises by the bonus, the finalized earned streak reflects it, and NO orphaned shield is left.
    function test_ActivityBoonDuringAfking_RoutesToSubStreakBase_NoOrphanShield() public {
        address p = makeAddr("boon_afker");

        // ---- Arm a live afking run with a manual streak parked just below a century boundary. ----
        // Park the dormant manual streak at 95 (lastSyncDay non-zero, day anchors 0 so _questSyncState skips
        // its decay branch and leaves the value verbatim). The +10 bonus below crosses the 100 century.
        _setManualQuestStreak(p, 95);
        _grantDeityPass(p);
        _fundPool(p, 50 ether);
        _subscribeLootbox(p, 1); // beginAfking: afkingActive = true; snapshots state.streak (95) into the latch
        // Deliver one funded day so the run is LIVE (afkingStartDay != 0) -- the precondition the boon hits via an
        // afking auto-open, and the precondition recordAfkingSecondary requires to be non-vacuous.
        _deliverDay(0xB00FA1);
        assertGt(_afkingStartOf(p), 0, "non-vacuity: a live afking run grounds the streak-bonus routing path");
        assertTrue(_afkingActiveOf(p), "non-vacuity: quest state marks the player mid afking-run");

        // Snapshot the protocol's pay-the-afker value (the afking sub streak base) BEFORE the bonus.
        uint256 subBaseBefore = _streakLatch16Of(p);
        uint8 shieldBefore = _streakShieldOf(p);
        assertEq(shieldBefore, 0, "non-vacuity: no streak shield held before the bonus");

        // ---- Fire the activity-boon streak award exactly as the boon module reaches it (onlyGame). ----
        // +10 takes the transient manual streak 95 -> 105, crossing the century-100 boundary.
        uint16 amount = 10;
        uint24 currentDay = uint24(game.currentDayView());
        vm.prank(ContractAddresses.GAME);
        quests.awardQuestStreakBonus(p, amount, currentDay);

        // ===================================================================
        // (a) VALUE LOSS: the afking sub streak base (what actually pays the afker) is UNCHANGED.
        //     CURRENT (buggy) code: writes the dormant state.streak, never the sub base -> base unchanged (FAIL).
        //     FIXED code: routes to recordAfkingSecondary -> base += amount.
        // ===================================================================
        uint256 subBaseAfter = _streakLatch16Of(p);
        assertEq(
            subBaseAfter,
            subBaseBefore + amount,
            "(a) the activity-boon bonus reaches the afking sub streak base (the value that pays the afker)"
        );

        // ===================================================================
        // (b) ORPHANED SHIELD: with the FIX no century shield is granted off the dormant manual streak while
        //     afking (the shield is earned once off the reconciled value at finalize). CURRENT (buggy) code
        //     grants one here off the transient 105 -> 1 shield (FAIL).
        // ===================================================================
        assertEq(
            _streakShieldOf(p),
            shieldBefore,
            "(b) no century shield is granted off the dormant manual streak while afking"
        );

        // ---- Finalize the run (explicit cancel) and confirm the post-finalize state is consistent. ----
        // The Game-side earned streak finalize will receive = the live afking streak (sub base, now incl. the
        // bonus under the fix, + funded delivered days). Read it just before cancel.
        uint256 earnedExpected = _liveAfkingStreakOf(p);
        assertGe(earnedExpected, subBaseAfter, "non-vacuity: the earned streak rides the (bonus-inclusive) sub base");
        vm.prank(p);
        game.subscribe(address(0), false, false, 0, 0, address(0)); // explicit cancel -> finalizeAfking

        // finalizeAfking writes the earned streak into the manual `state.streak` (slot off9). Read it DIRECTLY
        // (not via effectiveBaseStreakAndAfking, which would return the stale start-of-day baseStreak snapshot
        // taken at the parked 95 before the run was finalized).
        uint256 finalizedStreak = _manualStreakSlotOf(p);
        // The bonus survives into the earned streak because it rode the sub streak base; finalize hands it back.
        // Under the buggy code the bonus was on the dormant manual streak and was OVERWRITTEN here, so finalize
        // would hand back earned-without-bonus (one century lower) -- this asserts the bonus is reflected ONCE.
        assertEq(finalizedStreak, earnedExpected, "finalize hands back the earned streak (which now includes the bonus)");

        // No orphaned/double-credited century shield: the shield count and high-water must be EXACTLY what the
        // finalized streak's century justifies (here streak 106 -> century 1 -> exactly one shield, high-water 1),
        // never inflated by a shield granted off the transient pre-finalize manual streak.
        assertEq(
            uint256(_highWaterOf(p)),
            finalizedStreak / 100,
            "high-water matches the finalized streak's century (no orphan from a discarded transient streak)"
        );
        assertEq(
            uint256(_streakShieldOf(p)),
            finalizedStreak / 100,
            "exactly one century shield per finalized century - no orphaned/double-credited shield from the bonus"
        );
    }

    // =========================================================================
    // Reads
    // =========================================================================

    /// @dev The afking sub streak base -- post-PACK uint16 subStreakLatch (off 30) in the Game _subOf slot.
    function _streakLatch16Of(address who) internal view returns (uint256) {
        return _subField(who, OFF_STREAKLATCH, 16);
    }

    function _afkingStartOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_AFKINGSTART, 24));
    }

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 pk = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return pk & ((uint256(1) << widthBits) - 1);
    }

    /// @dev The live afking compute-on-read streak (base + funded delivered days) while the last covered day is
    ///      no older than yesterday -- mirrors GameAfkingModule._afkingStreak so the finalize hand-back is checked
    ///      against the same value the contract earns.
    function _liveAfkingStreakOf(address who) internal view returns (uint256) {
        uint256 covered = _subField(who, 17, 24); // afkCoveredThroughDay u24 off17
        uint256 today = game.currentDayView();
        if (today == 0 || covered + 1 < today) return 0;
        return _streakLatch16Of(who) + covered - _afkingStartOf(who);
    }

    // ---- questPlayerState (DegenerusQuests slot 1) reads ----

    function _questField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 pk = uint256(vm.load(address(quests), keccak256(abi.encode(who, QUESTSTATE_SLOT)))) >> (off * 8);
        return pk & ((uint256(1) << widthBits) - 1);
    }

    function _streakShieldOf(address who) internal view returns (uint8) {
        return uint8(_questField(who, OFF_QS_SHIELD, 8));
    }

    function _highWaterOf(address who) internal view returns (uint8) {
        return uint8(_questField(who, OFF_QS_HIGHWATER, 8));
    }

    function _afkingActiveOf(address who) internal view returns (bool) {
        return _questField(who, 13, 8) != 0; // afkingActive bool off13
    }

    /// @dev The manual quest streak `state.streak` (DegenerusQuests slot 1, off 9) read DIRECTLY -- the value
    ///      finalizeAfking writes back. Not effectiveBaseStreakAndAfking: that returns the stale start-of-day
    ///      baseStreak snapshot (taken at the parked pre-run value), which finalize does not refresh.
    function _manualStreakSlotOf(address who) internal view returns (uint256) {
        return _questField(who, OFF_QS_STREAK, 16);
    }

    // =========================================================================
    // Writers
    // =========================================================================

    /// @dev Park `who`'s dormant manual quest streak at `q` (lastSyncDay non-zero, day anchors 0) so
    ///      _questSyncState skips its decay branch and leaves `q` verbatim, and beginAfking snapshots `q`.
    function _setManualQuestStreak(address who, uint16 q) internal {
        bytes32 slot = keccak256(abi.encode(who, QUESTSTATE_SLOT));
        uint256 word = (uint256(q) << (OFF_QS_STREAK * 8)) | (uint256(1) << (OFF_QS_SYNCDAY * 8));
        vm.store(address(quests), slot, bytes32(word));
    }

    // =========================================================================
    // Afking-run drive helpers (ported from StreakSnapshotAndPendingFlipClamp)
    // =========================================================================

    /// @dev Deliver ONE funded day to the live sub set: a new-day STAGE buy + settle clean + open the pending box
    ///      so the no-orphan guard does not skip the next day's buy.
    function _deliverDay(uint256 vrfWord) internal {
        uint256 w = uint256(keccak256(abi.encode("dlv", vrfWord, _deliverNonce++))) | 1;
        _runStageNewDay(w);
        _settleClean(uint256(keccak256(abi.encode("dlvc", w))) | 1);
        vm.prank(makeAddr("deliver_opener"));
        game.openBoxes(400);
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
        game.subscribe(address(0), false, false, q, 0, address(0)); // self, lootbox mode, no reinvest
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
}
