// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {QuestInfo} from "../../contracts/interfaces/IDegenerusQuests.sol";

/// @title QuestRetryDoubleRoll -- a cross-midnight daily RETRY must not re-force a quest
/// @notice The foil daily is rolled at the final-jackpot RNG REQUEST — the boundary where
///         ticket routing flips to the next level. A 12h VRF retry re-requests a word for a
///         transition that ALREADY happened, and if it crosses the simulated-day boundary it
///         carries the NEW wall day (no RNGREUSE clamp arm engages while a request is pending:
///         rngWordCurrent is 0). Ungated, that second request rolls a SECOND consecutive
///         forced slot-1 quest — a foil daily whose one-per-cycle slot the first day's quest
///         may already have spent (uncompletable, FoilAlreadyBought), or on a turbo arming day
///         a forced decimator via the retry-preserved decDayOneActive. Either bills a rolled
///         miss. Pre-change behaviour rolled nothing here (the fulfilment-side force is gated
///         on gapDays == 0); `!isDailyRetry` in _finalizeRngRequest restores that, and this
///         pins it.
///
/// @dev Falsification: reverting the `!isDailyRetry` gate makes
///      test_crossMidnightRetryDoesNotRerollQuest fail with the day-D+1 slot-1 stamp.
///      test_finalJackpotRequestDoesRollTheFoilDaily is the non-vacuity control — it proves the
///      fixture really reaches a final-jackpot request that DOES roll the forced quest, so a
///      green retry test cannot be an artifact of never arming the roll at all.
contract QuestRetryDoubleRoll is DeployProtocol {
    /// @dev prizePoolsPacked slot: [future:128 | next:128] (see RngRetryLootboxStall).
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;

    uint8 private constant QUEST_TYPE_MINT_ETH = 1;
    uint8 private constant QUEST_TYPE_FOIL = 4;
    uint8 private constant QUEST_TYPE_DECIMATOR = 5;

    address private buyer;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        buyer = makeAddr("questretry_buyer");
        vm.deal(buyer, 1_000_000 ether);
        vm.deal(address(game), 5_000 ether);
        mockVRF.fundSubscription(1, 1_000 ether);
    }

    // ==================== Tests ====================

    /// @notice Non-vacuity control: the final-jackpot request really does force slot 1 to the
    ///         foil (or, on an arming day, the decimator) daily. Without this, a passing retry
    ///         test could simply mean the fixture never armed a roll.
    function test_finalJackpotRequestDoesRollTheFoilDaily() public {
        _driveToLastPurchaseDay();
        (bool rolled, uint8 rolledType, ) = _driveToFinalJackpotRequest();
        assertTrue(rolled, "fixture never reached a rolling final-jackpot request");
        assertTrue(
            rolledType == QUEST_TYPE_FOIL || rolledType == QUEST_TYPE_DECIMATOR,
            "final-jackpot request did not force a foil/decimator slot-1 quest"
        );
    }

    /// @notice The 12h retry, fired on the NEXT wall day, must roll nothing: the day it
    ///         carries must stay unrolled exactly as the pre-change fulfilment path left it.
    function test_crossMidnightRetryDoesNotRerollQuest() public {
        _driveToLastPurchaseDay();
        (bool rolled, uint8 rolledType, uint24 rolledDay) = _driveToFinalJackpotRequest();
        assertTrue(rolled, "fixture never reached a rolling final-jackpot request");
        assertTrue(game.rngLocked(), "final-jackpot request should leave the daily lock held");

        // Cross midnight AND the 12h retry timeout with the word still unfulfilled, then let
        // anyone fire the retry. The daily request is still pending, so this is the retry
        // branch (rngRequestTime LSB still 0).
        vm.warp(block.timestamp + 1 days + 1 hours);
        (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
        assertTrue(ok, "retry advance reverted");

        QuestInfo[2] memory after_ = quests.getActiveQuests();
        assertEq(
            uint256(after_[1].day),
            uint256(rolledDay),
            "retry rolled a NEW day's slot-1 quest (double-roll regression)"
        );
        assertEq(
            uint256(after_[1].questType),
            uint256(rolledType),
            "retry changed the standing slot-1 quest type"
        );
        assertEq(uint256(after_[0].questType), uint256(QUEST_TYPE_MINT_ETH), "slot 0 must stay MINT_ETH");
    }

    // ==================== Helpers ====================

    /// @dev Drive to a last-purchase-day window with RNG unlocked (mirrors
    ///      RngRetryLootboxStall._driveToLastPurchaseDay).
    function _driveToLastPurchaseDay() internal returns (uint24) {
        uint256 simTime = block.timestamp;
        for (uint256 day = 0; day < 800; day++) {
            require(!game.gameOver(), "gameOver before reaching last-purchase-day");

            (, , bool lpd, bool rngL, ) = game.purchaseInfo();
            if (game.level() >= 1 && lpd && !rngL) return game.level();

            simTime += 1 days + 1;
            vm.warp(simTime);
            _seedNextPrizePool(49.9 ether);
            _buyTickets(buyer, 4000);

            for (uint256 j = 0; j < 80; j++) {
                _fulfillVrfIfPending();
                (, , bool lpd2, bool rngL2, ) = game.purchaseInfo();
                if (game.level() >= 1 && lpd2 && !rngL2) return game.level();
                (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
                if (!ok) break;
            }
        }
        revert("did not reach a last-purchase-day window");
    }

    /// @dev From a last-purchase-day window, drive forward until the FINAL-jackpot RNG
    ///      request fires and leave its word UNFULFILLED (lock held), which is the only state
    ///      the 12h retry branch can be reached from. Note a plain transition request is NOT
    ///      final: `finalJackpotRequest` needs jackpotCounter + jpStep >= JACKPOT_LEVEL_CAP,
    ///      true at a turbo single-day collapse or on the last of a phase's jackpot days.
    ///      Returns whether such a request rolled a forced slot-1 quest, plus its type/day.
    function _driveToFinalJackpotRequest()
        internal
        returns (bool rolled, uint8 rolledType, uint24 rolledDay)
    {
        uint256 simTime = block.timestamp;
        for (uint256 day = 0; day < 60; day++) {
            simTime += 1 days + 1;
            vm.warp(simTime);

            for (uint256 j = 0; j < 30; j++) {
                QuestInfo[2] memory pre = quests.getActiveQuests();
                (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
                if (!ok) break;

                QuestInfo[2] memory post = quests.getActiveQuests();
                bool forced = post[1].questType == QUEST_TYPE_FOIL ||
                    post[1].questType == QUEST_TYPE_DECIMATOR;

                // The request-side roll: a forced slot-1 quest stamped with a NEW day while
                // the daily lock is held and this day's word is still unfulfilled.
                if (forced && post[1].day != pre[1].day && game.rngLocked()) {
                    uint256 rid = mockVRF.lastRequestId();
                    if (rid != 0) {
                        (, , bool fulfilled) = mockVRF.pendingRequests(rid);
                        if (!fulfilled) return (true, post[1].questType, post[1].day);
                    }
                }

                if (game.rngLocked()) _fulfillVrfIfPending();
                if (game.gameOver()) return (false, 0, 0);
            }
        }
        return (false, 0, 0);
    }

    function _buyTickets(address who, uint256 qty) internal {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_ || game.gameOver()) return;
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;
        if (who.balance < cost) vm.deal(who, cost + 10 ether);
        vm.prank(who);
        try game.purchase{value: cost}(who, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
    }

    function _fulfillVrfIfPending() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 randomWord = uint256(keccak256(abi.encode(block.timestamp, game.level(), reqId)));
        try mockVRF.fulfillRandomWords(reqId, randomWord) {} catch {}
    }

    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint256 currentNext = packed & ((uint256(1) << 128) - 1);
        if (currentNext >= targetNext) return;
        vm.store(
            address(game),
            bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)),
            bytes32((packed & ~((uint256(1) << 128) - 1)) | targetNext)
        );
    }
}
