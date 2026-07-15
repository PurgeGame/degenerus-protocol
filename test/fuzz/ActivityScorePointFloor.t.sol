// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @title ActivityScorePointFloorTest -- proves the whole-point activity score's sole sub-point leg
///        (the quest streak) floors at `floor(questStreak/2)`, that this point-domain leg is the exact
///        integer image of the retired `questStreak*50` bps leg, and that the manual quest streak and the
///        live afking-run streak base feed the score through ONE exact integer path with afking-XOR-manual
///        exclusivity.
///
/// @notice The score is now whole points end-to-end; the only place precision is intentionally dropped is
///   the quest-streak leg (`bonusPoints += questStreak / 2`, DegenerusGameMintStreakUtils._playerActivityScoreAt).
///   A round-half-up policy (5 -> 3) or a 0.5-pt-granular representation would diverge from the floored value
///   asserted here, so each assertion fails-without the shipped floor.
///
/// @dev Drives `game.playerActivityScore` (the public getter reaching `_playerActivityScoreAt`) against a
///   fresh fixture where a player's ONLY score contributor is a known quest streak: at deploy `level == 0`,
///   so `_mintCountBonusPoints` returns 0 and the affiliate cached leg reads 0, a fresh player carries no
///   deity pass / whale pass / curse, and `_mintStreakEffectiveFromPacked` returns 0 — the quest leg is the
///   whole score. The manual streak is reached by writing `questPlayerState[player]` directly (the same
///   decay-aware value `effectiveBaseStreakAndAfking` reads), with the day anchors left 0 so the decay branch
///   is inert and `state.streak` reads straight through. Test-only: ZERO contracts/*.sol mutation.
contract ActivityScorePointFloorTest is DeployProtocol {
    /// @dev questPlayerState mapping root (slot 1 in DegenerusQuests; the per-player PlayerQuestState packs
    ///      into one slot). Byte offsets within that slot: lastCompletedDay u24 off0, lastActiveDay u24 off3,
    ///      lastSyncDay u24 off6, streak u16 off9, baseStreak u16 off11, afkingActive bool off13.
    uint256 private constant QUESTSTATE_SLOT = 1;
    uint256 private constant OFF_QS_SYNCDAY = 6;
    uint256 private constant OFF_QS_STREAK = 9;

    /// @dev Game-resident slots + the POST-PACK Sub-slot accumulator offsets (re-derived from the v69
    ///      storageLayout, NOT the pre-PACK V56 offsets): _subOf mapping root @ slot 54; mintPacked_ deity
    ///      bit @ bit 184. The accumulator section after the repack is affiliateBase u32 off23,
    ///      pendingFlip u24 off27, subStreakLatch u16 off30 (the latch widened 8->16, pendingFlip narrowed
    ///      32->24). The two afking day markers are afkCoveredThroughDay u24 off17, afkingStartDay u24 off20.
    uint256 private constant SUBOF_SLOT = 54;
    uint256 private constant MINTPACKED_SLOT = 9;
    uint256 private constant DEITY_SHIFT = 184;
    uint256 private constant OFF_AFKCOVERED = 16;
    uint256 private constant OFF_AFKINGSTART = 19;
    uint256 private constant OFF_STREAKLATCH = 29;

    /// @dev A deity-passed player with no quest streak scores exactly 50 + 25 + 80 = 155 points (the deity
    ///      base plus the deity activity bonus), with zero affiliate/whale/curse contribution — so the quest
    ///      leg of a deity afker's score is precisely `score - 155`.
    uint256 private constant DEITY_BASELINE_POINTS = 155;

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
    // Task 1 — the quest-streak floor rule + the bps-equivalence identity
    // =========================================================================

    /// @notice The point-domain quest-streak leg `floor(questStreak/2)` is the exact integer image of the
    ///         retired bps leg `floor((questStreak*50)/100)` at every streak on the grid, and the floor drops
    ///         the trailing half-point at odd counts. Asserting `q/2` explicitly at the odd boundaries means a
    ///         round-half-up regression (5 -> 3, 7 -> 4) would fail this test — the floor is pinned, not merely
    ///         the identity.
    function test_QuestStreakFloorRule_BpsEquivalence() public pure {
        uint256[18] memory grid = [
            uint256(0), 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 49, 50, 51, 100, 255, 1000, 32767
        ];

        // D-02 identity: the point leg equals the integer hundredths of the old bps leg for every streak.
        // Both are uint256 integer divisions, so bit-equality here is the whole equivalence claim.
        for (uint256 i; i < grid.length; i++) {
            uint256 q = grid[i];
            assertEq(q / 2, (q * 50) / 100, "point leg q/2 == integer hundredths of the old bps leg (q*50)/100");
        }

        // Even streaks keep the full point; odd streaks drop the trailing half-point. A round-half-up
        // implementation would give 5 -> 3 / 7 -> 4 (rejected); a 0.5-pt-granular score would carry the
        // half-point at all (also rejected). Pinning the floored values makes either regression fail.
        assertEq(uint256(4) / 2, 2, "even streak keeps the full point (4 -> 2)");
        assertEq(uint256(5) / 2, 2, "odd streak drops the trailing half-point (5 -> 2, not the round-half-up 3)");
        assertEq(uint256(6) / 2, 3, "even streak keeps the full point (6 -> 3)");
        assertEq(uint256(7) / 2, 3, "odd streak drops the trailing half-point (7 -> 3, not the round-half-up 4)");
    }

    /// @notice End-to-end, the public `playerActivityScore` quest leg is exactly `floor(questStreak/2)`.
    ///         A fresh player whose sole contributor is a manual quest streak of an ODD value reads back a
    ///         clean whole-point score that drops the trailing half-point: streak 7 -> score 3 (not 3.5, not
    ///         the round-half-up 4). The even-vs-odd differences (6 vs 7 -> +0, 8 vs 9 -> +0, 8 vs 10 -> +1)
    ///         independently witness that the odd half-point never reaches the score.
    function test_QuestStreakLegIsoEndToEnd() public {
        // Non-vacuity: a fresh player has a zero score, so any streak contribution stands alone.
        address fresh = makeAddr("floor_fresh");
        assertEq(game.playerActivityScore(fresh), 0, "fresh player has no score contributor (quest leg isolated)");

        // Odd streak 7: the score is exactly floor(7/2) = 3. A 0.5-pt-granular score (3.5-equivalent) or a
        // round-half-up score (4) would not equal 3.
        address odd = makeAddr("floor_odd7");
        _setManualQuestStreak(odd, 7);
        assertEq(_effectiveStreakSeenByScore(odd), 7, "the score reads the driven manual streak of 7");
        assertEq(game.playerActivityScore(odd), 3, "odd streak 7 -> clean whole-point score floor(7/2) = 3");

        // Even/odd difference pairs: the odd member contributes the SAME points as the even one below it
        // (the half-point is dropped), and a +2 streak step adds exactly one point.
        address e6 = makeAddr("floor_e6");
        address o7 = makeAddr("floor_o7");
        address e8 = makeAddr("floor_e8");
        address o9 = makeAddr("floor_o9");
        address e10 = makeAddr("floor_e10");
        _setManualQuestStreak(e6, 6);
        _setManualQuestStreak(o7, 7);
        _setManualQuestStreak(e8, 8);
        _setManualQuestStreak(o9, 9);
        _setManualQuestStreak(e10, 10);

        uint256 s6 = game.playerActivityScore(e6);
        uint256 s7 = game.playerActivityScore(o7);
        uint256 s8 = game.playerActivityScore(e8);
        uint256 s9 = game.playerActivityScore(o9);
        uint256 s10 = game.playerActivityScore(e10);

        assertEq(s7 - s6, 0, "6 vs 7: the odd half-point is dropped (floor(7/2) - floor(6/2) == 0)");
        assertEq(s9 - s8, 0, "8 vs 9: the odd half-point is dropped (floor(9/2) - floor(8/2) == 0)");
        assertEq(s10 - s8, 1, "8 vs 10: a +2 streak step adds exactly one whole point");
    }

    // =========================================================================
    // Shared drive helpers
    // =========================================================================

    /// @dev Drive `player`'s effective quest streak to `q` by writing the dormant manual streak directly into
    ///      `questPlayerState[player]`. `state.streak` is set to `q`; `lastSyncDay` is set to a non-zero value
    ///      while the day anchors (lastActiveDay / lastCompletedDay) stay 0, so `_effectiveBaseStreak` skips
    ///      its decay branch (anchorDay == 0) and the non-synced path returns `state.streak` verbatim. The
    ///      player is a non-afker (afkingActive == 0), so `_effectiveQuestStreak` returns this manual streak
    ///      with no Sub-slot read — the score's sole contributor.
    function _setManualQuestStreak(address player, uint16 q) internal {
        bytes32 slot = keccak256(abi.encode(player, QUESTSTATE_SLOT));
        uint256 word = (uint256(q) << (OFF_QS_STREAK * 8)) | (uint256(1) << (OFF_QS_SYNCDAY * 8));
        vm.store(address(quests), slot, bytes32(word));
    }

    /// @dev The effective quest streak the activity score reads for `player` — the same value
    ///      `_effectiveQuestStreak` resolves (manual for a non-afker, live compute-on-read for an afker).
    function _effectiveStreakSeenByScore(address player) internal view returns (uint32 streak) {
        (streak, ) = quests.effectiveBaseStreakAndAfking(player);
    }

    // =========================================================================
    // Task 2 — the single exact integer streak path + afking-XOR-manual exclusivity
    // =========================================================================

    /// @notice Exactly one streak source feeds the score at a time. While an afking run is LIVE, the score's
    ///         quest leg is the compute-on-read `_streakBaseOf + (covered - afkingStartDay)`; after a missed
    ///         funded day decays the run, the score falls back to the dormant manual streak. The live value
    ///         and the manual value are chosen to floor to DIFFERENT points (live 9 -> 4, manual 4 -> 2), so a
    ///         summed-both-sources implementation (4 + 2 = 6) or a stuck-on-one-source implementation would
    ///         fail: the live phase must read 4 and the post-decay phase must read 2.
    function test_LiveAfkingStreakFeedsScore_XOR() public {
        address p = makeAddr("xor_afker");
        uint16 manualStreak = 4; // dormant manual: floors to 2, distinct from the live value's floor
        _setManualQuestStreak(p, manualStreak);
        _grantDeityPass(p);
        _fundPool(p, 400 ether);
        _subscribeLootbox(p, 1);

        // Deliver funded days until the live compute-on-read streak reaches an ODD value >= 9, then read the
        // score while the run is still live (the delivery covers the current day, so covered + 1 >= today).
        uint32 liveStreak;
        uint256 liveScore;
        bool reachedLive;
        for (uint256 d; d < 16; d++) {
            _deliverDay(_singleton(p), uint256(keccak256(abi.encode("xor_dd", d))) | 1);
            liveStreak = _liveAfkingStreakOf(p);
            if (liveStreak >= 9 && liveStreak % 2 == 1) {
                liveScore = game.playerActivityScore(p);
                reachedLive = true;
                break;
            }
        }
        assertTrue(reachedLive, "non-vacuity: the run reached a live odd streak >= 9");

        // LIVE: the score reads the live afking value, not the manual snapshot. live=9 -> floor(9/2)=4, which
        // differs from the manual fallback floor(4/2)=2, so this distinguishes the two sources.
        assertEq(liveScore - DEITY_BASELINE_POINTS, uint256(liveStreak) / 2, "live: the quest leg is floor(liveAfkingStreak/2)");
        assertEq(liveScore - DEITY_BASELINE_POINTS, 4, "live: floor(9/2) = 4 (the live source, not the manual floor(4/2)=2)");

        // Induce a decay gap: advance funded days with NO delivery so the last covered day falls more than one
        // day behind (covered + 1 < currentDay) and `_liveAfkingStreak` decays to 0.
        _skipDaysNoDelivery(0x0DECA1);
        _skipDaysNoDelivery(0x0DECA2);
        _skipDaysNoDelivery(0x0DECA3);
        assertEq(_liveAfkingStreakOf(p), 0, "the run decayed (live afking streak read is 0 after a missed funded day)");

        // POST-DECAY: the score now reads the dormant manual streak (4 -> floor 2), proving exactly one source
        // feeds the score — the live value (which floored to 4) is gone, never summed onto the fallback.
        uint256 postScore = game.playerActivityScore(p);
        assertEq(postScore - DEITY_BASELINE_POINTS, uint256(manualStreak) / 2, "post-decay: the quest leg falls back to floor(manualStreak/2)");
        assertEq(postScore - DEITY_BASELINE_POINTS, 2, "post-decay: floor(4/2) = 2 (the manual source, not the lapsed live 4)");
    }

    /// @notice The live afking streak combines through one exact integer path with no fractional intermediate:
    ///         an ODD total streak yields a clean whole-point score whose quest leg is `floor(total/2)`, with
    ///         the trailing half-point dropped. A half-point intermediate anywhere in the base + funded-days
    ///         combine (the retired `*50` bps path could carry one) would surface a non-floored value here.
    function test_ExactIntegerCombine_NoFractionalIntermediate() public {
        address p = makeAddr("combine_afker");
        _setManualQuestStreak(p, 0); // no manual snapshot: the base starts at 0, so live == covered - start
        _grantDeityPass(p);
        _fundPool(p, 400 ether);
        _subscribeLootbox(p, 1);

        // Drive the live compute-on-read streak to an odd total, reading the score while live.
        uint32 total;
        uint256 score;
        bool reached;
        for (uint256 d; d < 16; d++) {
            _deliverDay(_singleton(p), uint256(keccak256(abi.encode("comb_dd", d))) | 1);
            total = _liveAfkingStreakOf(p);
            if (total >= 5 && total % 2 == 1) {
                score = game.playerActivityScore(p);
                reached = true;
                break;
            }
        }
        assertTrue(reached, "non-vacuity: the run reached a live odd total >= 5");

        // The whole-point score's quest leg is exactly floor(total/2) — the odd half-point is dropped, and the
        // score is a clean integer (no 0.5-pt residue is even representable, and a fractional combine would
        // have surfaced as score - 155 != floor(total/2)).
        assertEq(score - DEITY_BASELINE_POINTS, uint256(total) / 2, "odd total -> clean whole-point quest leg floor(total/2)");
        assertEq((score - DEITY_BASELINE_POINTS) * 2 + 1, total, "the dropped trailing half-point: 2*floor(total/2) + 1 == odd total");
    }

    // =========================================================================
    // Afking-run drive helpers (ported from V56SecUnmanipulable, re-pointed to the post-PACK Sub offsets)
    // =========================================================================

    /// @dev The live afking compute-on-read streak the score reads for `player`: `_streakBaseOf + (covered -
    ///      afkingStartDay)` while the last covered day is no older than yesterday, else 0 (decay-on-read).
    ///      Mirrors `_afkingStreak` off the post-PACK Sub slot so the test reads the same value the score does.
    function _liveAfkingStreakOf(address player) internal view returns (uint32) {
        uint32 covered = _afkCoveredOf(player);
        uint32 today = game.currentDayView();
        if (today == 0 || covered + 1 < today) return 0;
        return _streakBaseOf(player) + covered - _afkingStartOf(player);
    }

    /// @dev Deliver ONE funded day to `who`: a new-day STAGE buy (stamps the box + accrues + advances the
    ///      covered high-water), settle clean, then open the pending box so the no-orphan guard does not skip
    ///      the next day's buy. Each delivered day advances the live afking streak by one.
    function _deliverDay(address[] memory who, uint256 vrfWord) internal {
        uint256 w = uint256(keccak256(abi.encode("dlv", vrfWord, _deliverNonce++))) | 1;
        _runStageNewDay(w);
        _settleClean(uint256(keccak256(abi.encode("dlvc", w))) | 1);
        vm.prank(makeAddr("deliver_opener"));
        game.openBoxes(400);
        who;
    }

    /// @dev Warp forward one simulated day WITHOUT delivering a buy — manufactures the decay gap.
    function _skipDaysNoDelivery(uint256 vrfWord) internal {
        uint256 w = uint256(keccak256(abi.encode("skip", vrfWord, _deliverNonce++))) | 1;
        _runStageNewDay(w);
        _settleClean(uint256(keccak256(abi.encode("skipc", w))) | 1);
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

    // ---- Sub-slot reads (the post-PACK offsets) ----

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _afkCoveredOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_AFKCOVERED, 24));
    }

    function _afkingStartOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_AFKINGSTART, 24));
    }

    /// @dev The afking-run streak base — the FULL post-PACK uint16 latch (off 30, width 16).
    function _streakBaseOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_STREAKLATCH, 16));
    }
}
