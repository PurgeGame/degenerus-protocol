// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {QaSlots} from "../helpers/QaSlots.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {activityScoreOf} from "../helpers/ActivityScoreOf.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";

/// @notice A foil pack freezes an activity score whose quest-streak leg counts a streak of at
///         least 12, the floor the pack also gives the streak itself:
///         - a manual buyer below 12 freezes the score and multiplier a streak of exactly 12 gives;
///         - a manual buyer above 12 freezes its own streak;
///         - a subscriber in a live AFKing run freezes the score its floored run streak gives.
///         Full protocol: every pack is a real `purchaseOrderFor` foil purchase and the frozen
///         values are read from the stored foil record through the lens. Only the manual quest
///         streak is written with vm.store.
contract FoilScoreUsesFloor is DeployProtocol {
    /// @dev questPlayerState mapping root in DegenerusQuests; byte offsets within the packed
    ///      PlayerQuestState: lastSyncDay u24 off6, streak u16 off9, baseStreak u16 off11.
    uint256 private constant QUESTSTATE_SLOT = QaSlots.STATE;
    uint256 private constant OFF_QS_SYNCDAY = 6;
    uint256 private constant OFF_QS_STREAK = 9;
    uint256 private constant OFF_QS_BASESTREAK = 11;

    uint256 private constant FOIL_STREAK_FLOOR = 12;

    DegenerusGameLens private lens;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 5_000_000 ether);
        lens = new DegenerusGameLens();
        _finishSubscriptionWindow();
    }

    // =====================================================================
    // Helpers
    // =====================================================================

    /// @dev Drive `player`'s effective manual quest streak to `q`: streak and baseStreak both
    ///      carry `q`, lastSyncDay is a past day and the day anchors stay 0, so the decay branch
    ///      is inert and both the unsynced read and the day's snapshot return `q`.
    function _setManualQuestStreak(address player, uint16 q) internal {
        uint32 id = game.walletIdOf_g3120(player);
        if (id == 0) id = _giveWalletId(player);
        bytes32 slot = keccak256(abi.encode(uint256(id), QUESTSTATE_SLOT));
        uint256 word = (uint256(q) << (OFF_QS_STREAK * 8)) |
            (uint256(q) << (OFF_QS_BASESTREAK * 8)) |
            (uint256(1) << (OFF_QS_SYNCDAY * 8));
        vm.store(address(quests), slot, bytes32(word));
    }

    /// @dev A manual buyer whose effective quest streak is `q` at its foil purchase.
    function _manualBuyer(string memory label, uint16 q) internal returns (address who) {
        who = makeAddr(label);
        _setManualQuestStreak(who, q);
        (uint32 seen, bool afking) =
            quests.effectiveBaseStreakAndAfking_g1521(game.walletIdOf_g3120(who), _fixtureGameDay());
        assertEq(uint256(seen), uint256(q), "fixture: the score reads the driven manual streak");
        assertFalse(afking, "fixture: a manual buyer");
    }

    /// @dev Buy one foil pack for `who` and return the score and multiplier its record froze.
    function _buyFoil(address who) internal returns (uint256 score, uint256 multBps) {
        vm.deal(who, 1_000 ether);
        vm.prank(who);
        game.purchaseOrderFor{value: 1 ether}(0, 0, 0, bytes32(0), MintPaymentKind.DirectEth, true);
        DegenerusGameLens.FoilRecordEntry memory f = lens.foilRecordOf(address(game), game.currentLvl(), who);
        if (!f.present) f = lens.foilRecordOf(address(game), game.currentLvl() + 1, who);
        assertTrue(f.present, "non-vacuity: the pack's record was written");
        return (f.activityScore, f.multBps);
    }

    /// @dev The live afking streak the score reads for `player`: the lane's checkpoint streak
    ///      plus the credited days past its checkpoint, 0 for a non-member.
    function _liveAfkingStreakOf(address player) internal view returns (uint32) {
        (uint256 lane, uint256 position1) = GameSlotKeys.subLane(address(game), game.walletIdOf_g3120(player));
        if (position1 == 0) return 0;
        uint256 day = (lane >> 46) & 0x3fffff;
        uint256 endpoint = (uint256(vm.load(address(game), bytes32(GameSlots.AFKING_ENDPOINT_DAY)))
            >> (GameSlots.AFKING_ENDPOINT_DAY_OFFSET * 8)) & 0xffffff;
        return uint32(((lane >> 69) & 0xffff) + (endpoint > day ? endpoint - day : 0));
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        uint32 id = game.walletIdOf_g3120(who);
        if (id == 0) id = _giveWalletId(who);
        game.depositAfkingFunding{value: amount}(id);
    }

    function _subscribeLootbox(address who, uint8 q) internal {
        uint256 seat = _grantSeat(who); // a new run burns a seat the subscriber holds
        vm.prank(who);
        game.subscribe(0, false, q, seat); // self, lootbox mode, no reinvest
    }

    // =====================================================================
    // Manual buyers
    // =====================================================================

    /// @notice A manual buyer whose streak is below the floor freezes the same score and
    ///         multiplier as an otherwise identical buyer whose streak is exactly 12.
    function test_ManualBuyerBelowFloorFreezesTheFloorScore() public {
        // Reference: a streak of exactly 12, which the floor neither raises nor lowers.
        (uint256 floorScore, uint256 floorMult) = _buyFoil(_manualBuyer("foil_at_floor", uint16(FOIL_STREAK_FLOOR)));
        // The reference score holds the 6 points a streak of 12 is worth.
        assertGe(floorScore, FOIL_STREAK_FLOOR / 2, "reference: 12 / 2 quest points are in the score");

        uint16[3] memory below = [uint16(0), 6, 11];
        for (uint256 i; i < below.length; ++i) {
            address who = _manualBuyer(string.concat("foil_below_", vm.toString(i)), below[i]);
            (uint256 score, uint256 multBps) = _buyFoil(who);
            // The frozen score counts the streak as 12, not as the buyer's lower streak.
            assertEq(score, floorScore, "below the floor: the frozen score is the streak-12 score");
            // The multiplier is derived from that score, so it matches the reference too.
            assertEq(multBps, floorMult, "below the floor: the frozen multiplier is the streak-12 one");
        }
    }

    /// @notice A manual buyer whose streak is above the floor freezes its own streak: 20 against
    ///         12 is 20 / 2 - 12 / 2 = 4 more points and, on the first curve segment, 400 bps.
    function test_ManualBuyerAboveFloorFreezesItsOwnStreak() public {
        (uint256 floorScore, uint256 floorMult) = _buyFoil(_manualBuyer("foil_ref_floor", uint16(FOIL_STREAK_FLOOR)));
        (uint256 score, uint256 multBps) = _buyFoil(_manualBuyer("foil_above", 20));

        // The floor leaves a higher streak alone: the score carries the full 10 quest points.
        assertEq(score, floorScore + 4, "above the floor: the frozen score uses the buyer's streak");
        // Fixture guard: both scores sit on the 100-bps-per-point segment of the foil curve.
        assertLe(score, 300, "fixture: first segment of the foil curve");
        // Four points on that segment are 400 bps of multiplier.
        assertEq(multBps, floorMult + 400, "above the floor: the multiplier follows the buyer's streak");
    }

    // =====================================================================
    // AFKing subscriber
    // =====================================================================

    /// @notice A subscriber in a live run freezes the score its run streak gives after the pack's
    ///         floor: the record equals the activity score read right after the purchase, which
    ///         reads the same floored run streak.
    function test_SubscriberFreezesItsFlooredRunStreak() public {
        address sub = makeAddr("foil_subscriber");
        _fundPool(sub, 50 ether);
        _subscribeLootbox(sub, 1);
        (, uint256 position1) = GameSlotKeys.subLane(address(game), game.walletIdOf_g3120(sub));
        assertGt(position1, 0, "fixture: a live run");
        assertLt(uint256(_liveAfkingStreakOf(sub)), FOIL_STREAK_FLOOR, "fixture: the run starts below the floor");

        (uint256 score, uint256 multBps) = _buyFoil(sub);

        // The pack floored the run streak before the score was frozen.
        assertGe(uint256(_liveAfkingStreakOf(sub)), FOIL_STREAK_FLOOR, "the run streak is at least the floor");
        // The frozen score is the one the floored run streak gives: the post-purchase activity
        // score reads that same run streak and the same post-purchase mint state.
        assertEq(score, activityScoreOf(address(game), sub), "subscriber: frozen score uses the run streak");
        // Fixture guard, then the first-segment curve: 20,000 bps plus 100 bps a point.
        assertLe(score, 300, "fixture: first segment of the foil curve");
        assertEq(multBps, 20_000 + 100 * score, "subscriber: the multiplier follows that score");
    }
}
