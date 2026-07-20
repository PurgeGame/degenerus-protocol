// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {QuestInfo} from "../../contracts/interfaces/IDegenerusQuests.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title QuestForcedTypesReachableTest -- FOIL and DECIMATOR quests actually roll.
///
/// @notice Two quest types are excluded from the random daily pool and reach
///         players only through a gate:
///         - FOIL (type 4) is forced onto slot 1 on the first purchase day of
///           a level. Its gate must be observable when the daily roll runs,
///           which happens early in the advance pass inside rngGate.
///         - DECIMATOR (type 5) is enabled while a decimator burn window is
///           open. The window is open while the stored level ends in 4 or 9;
///           the resolution level players burn into is that level + 1 (the
///           basis FLIP uses at FLIP.sol:664), which is what the availability
///           rule is written against.
///
/// @dev Drives real play from genesis with deterministic VRF words and samples
///      the rolled quest types every day, so it exercises the game loop's own
///      gate decisions rather than calling the roll with hand-supplied flags.
contract QuestForcedTypesReachableTest is DeployProtocol {
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;

    uint8 private constant QUEST_TYPE_FOIL = 4;
    uint8 private constant QUEST_TYPE_DECIMATOR = 5;

    address private buyer;
    uint256 private simTime;
    uint24 private trackLevel;
    uint256 private purchaseDaysAtLevel;

    // Observations across the drive
    bool private sawFoilDaily;
    bool private sawFoilInPurchasePhase;
    bool private sawDecimator;
    bool private sawDecimatorWhileWindowOpen;
    bool private sawArmingDay;
    bool private sawDecimatorOnArmingDay;
    uint256 private foilDays;
    // For each day the foil quest was forced: purchaseStartDay as it stood once
    // the day's advances finished. The transition stamps it with the day the
    // drain completes, so on a correct foil day it equals that very day.
    uint256[] private foilPsdAtDayEnd;
    uint256[] private foilQuestDays;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);

        buyer = makeAddr("questgate_buyer");
        vm.deal(buyer, 100_000 ether);
        vm.deal(address(game), 20_000 ether);
        simTime = vm.getBlockTimestamp();
    }

    // ==================== Drive helpers ====================

    function _seedNextPrizePool(uint256 targetNext) private {
        uint256 packed = uint256(
            vm.load(address(game), bytes32(PRIZE_POOLS_PACKED_SLOT))
        );
        uint128 currentNext = uint128(packed);
        if (uint256(currentNext) >= targetNext) return;
        uint128 currentFuture = uint128(packed >> 128);
        vm.store(
            address(game),
            bytes32(PRIZE_POOLS_PACKED_SLOT),
            bytes32((uint256(currentFuture) << 128) | targetNext)
        );
    }

    function _seedFuturePrizePool(uint256 targetFuture) private {
        uint256 packed = uint256(
            vm.load(address(game), bytes32(PRIZE_POOLS_PACKED_SLOT))
        );
        uint128 currentNext = uint128(packed);
        uint128 currentFuture = uint128(packed >> 128);
        if (uint256(currentFuture) >= targetFuture) return;
        vm.store(
            address(game),
            bytes32(PRIZE_POOLS_PACKED_SLOT),
            bytes32((targetFuture << 128) | uint256(currentNext))
        );
    }

    function _buyTickets(address who, uint256 qty) private {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_ || game.gameOver()) return;
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;
        if (who.balance < cost) vm.deal(who, cost + 10 ether);
        vm.prank(who);
        try
            game.purchase{value: cost}(
                who,
                qty,
                0,
                bytes32(0),
                MintPaymentKind.DirectEth,
                false
            )
        {} catch {}
    }

    function _fulfillVrf() private {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 word = uint256(
            keccak256(
                abi.encode(
                    "quest_gate_word",
                    vm.getBlockTimestamp(),
                    game.level(),
                    reqId
                )
            )
        );
        if (word == 0) word = 1;
        try mockVRF.fulfillRandomWords(reqId, word) {} catch {}
    }

    /// @dev One simulated day, then sample the rolled quest types.
    function _runDayAndSample() private {
        simTime += 1 days + 1;
        vm.warp(simTime);

        uint24 lvlNow = game.level();
        if (lvlNow != trackLevel || game.jackpotPhase()) {
            trackLevel = lvlNow;
            purchaseDaysAtLevel = 0;
        } else {
            purchaseDaysAtLevel++;
        }

        _seedNextPrizePool(49.9 ether);
        if (purchaseDaysAtLevel >= 4) {
            _seedNextPrizePool(game.prizePoolTargetView() + 1 ether);
        }
        _seedFuturePrizePool(100 ether);
        _buyTickets(buyer, 4000);

        for (uint256 j = 0; j < 80; j++) {
            _fulfillVrf();
            (bool ok, ) = address(game).call(
                abi.encodeWithSignature("advanceGame()")
            );
            if (!ok) break;
        }

        _sample();
    }

    function _sample() private {
        QuestInfo[2] memory active = quests.getActiveQuests();
        bool windowOpen = game.decWindow();
        bool inJackpot = game.jackpotPhase();
        // decDayOneActive is slot 0 byte [31:32] -- raised by the request that
        // arms a burn window, cleared by the next day's fresh request, so it
        // still reads true after the arming day's advances finish.
        bool armingDayThisDay = ((uint256(
            vm.load(address(game), bytes32(uint256(0)))
        ) >> 248) & 1) == 1;
        if (armingDayThisDay) sawArmingDay = true;

        for (uint256 s = 0; s < 2; s++) {
            uint8 t = active[s].questType;
            if (t == QUEST_TYPE_FOIL) {
                sawFoilDaily = true;
                foilDays++;
                if (!inJackpot) sawFoilInPurchasePhase = true;
                // purchaseStartDay is slot 0 bytes [0:3] (uint24).
                foilPsdAtDayEnd.push(
                    uint256(
                        uint24(
                            uint256(
                                vm.load(address(game), bytes32(uint256(0)))
                            )
                        )
                    )
                );
                foilQuestDays.push(uint256(active[s].day));
            }
            if (t == QUEST_TYPE_DECIMATOR) {
                sawDecimator = true;
                if (windowOpen) sawDecimatorWhileWindowOpen = true;
            }
            if (s == 1 && armingDayThisDay && t == QUEST_TYPE_DECIMATOR) {
                sawDecimatorOnArmingDay = true;
            }
        }

        (uint8 lqType, , , , ) = quests.getPlayerLevelQuestView(buyer);
        if (lqType == QUEST_TYPE_DECIMATOR) {
            sawDecimator = true;
            if (windowOpen) sawDecimatorWhileWindowOpen = true;
        }
    }

    // ==================== Tests ====================

    /// @notice The forced buy-a-foil-pack daily reaches players. It is excluded
    ///         from the random pool, so the forced gate is its only route: if
    ///         the gate never reads true when the daily roll runs, the quest
    ///         type simply does not exist in the game.
    function testFoilDailyQuestActuallyRolls() public {
        for (uint256 d = 0; d < 200; d++) {
            if (game.gameOver()) break;
            if (game.level() > 5) break;
            _runDayAndSample();
        }
        assertGt(game.level(), 3, "drive crossed several level transitions");

        assertTrue(
            sawFoilDaily,
            "FOIL daily quest never rolled across multiple level transitions"
        );
        assertTrue(
            sawFoilInPurchasePhase,
            "FOIL daily rolled but never on a purchase-phase day"
        );
        // Once per level, not a stuck flag: the drive crossed several
        // transitions, and the forced day is a single day within each level.
        assertGe(foilDays, 2, "FOIL forced on more than one level");
        assertLe(
            foilDays,
            game.level() + 1,
            "FOIL forced at most once per level crossed"
        );

        // Day placement: the foil quest rolls on the day the purchase phase
        // OPENS -- the day carrying the level's final jackpot run, after which
        // the transition drains and reopens purchasing within that same day.
        // The transition stamps purchaseStartDay with the day it completes, so
        // on every forced foil day that stamp equals the day itself.
        for (uint256 i = 0; i < foilQuestDays.length; i++) {
            assertEq(
                foilPsdAtDayEnd[i],
                foilQuestDays[i],
                "FOIL forced on the day the purchase phase opens"
            );
        }
    }

    /// @notice The decimator quest reaches players while a burn window is open.
    ///         Availability is written against the resolution level (the level
    ///         burns key into), which is the stored level + 1 while a window is
    ///         open -- the same basis FLIP uses at FLIP.sol:664.
    function testDecimatorQuestRollsDuringBurnWindow() public {
        bool everOpen;
        for (uint256 d = 0; d < 200; d++) {
            if (game.gameOver()) break;
            if (game.level() > 5) break;
            _runDayAndSample();
            if (game.decWindow()) everOpen = true;
        }
        assertTrue(everOpen, "drive opened a decimator burn window");

        assertTrue(
            sawDecimator,
            "DECIMATOR quest never rolled despite an open burn window"
        );
        assertTrue(
            sawDecimatorWhileWindowOpen,
            "DECIMATOR quest rolled only outside the burn window"
        );

        // The day a window arms always carries the decimator quest in slot 1,
        // outranking the other forces that also target that day.
        assertTrue(sawArmingDay, "drive covered a window-arming day");
        assertTrue(
            sawDecimatorOnArmingDay,
            "arming day did not carry the DECIMATOR quest"
        );
    }
}
