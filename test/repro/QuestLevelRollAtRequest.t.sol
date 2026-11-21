// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {RngTags} from "../../contracts/libraries/RngTags.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {Vm} from "forge-std/Vm.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {QaSlots} from "../helpers/QaSlots.sol";

/// @notice The level quest rolls at the daily request that moves `level`, from the last applied
///         daily word under the QUEST_LEVEL tag. Right after that request, before the word
///         arrives and before consolidation, the entered level's quest is live: its version is
///         level + 1 and its ETH target is priced at level + 1, the price every handler passes.
contract QuestLevelRollAtRequest is DeployProtocol {
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = GameSlots.PRIZE_POOLS_PACKED;
    bytes32 private constant LEVEL_ROLLED = keccak256("LevelQuestRolled(uint24,uint24,uint8,uint256)");

    uint8 private constant MINT_ETH = 1;
    uint8 private constant FLIP = 2;
    uint8 private constant AFFILIATE = 3;
    uint8 private constant DECIMATOR = 5;
    uint8 private constant LOOTBOX = 6;
    uint8 private constant DEGENERETTE_ETH = 7;
    uint8 private constant DEGENERETTE_FLIP = 8;
    uint8 private constant CRAPS_DAY_PASS = 11;

    address private buyer;

    struct Roll {
        bool seen;
        uint24 questLevel;
        uint24 version;
        uint8 questType;
        uint256 target;
        uint256 priorWord;
        uint24 level;
    }

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        buyer = makeAddr("lq_request_buyer");
        vm.deal(buyer, 1_000_000 ether);
        vm.deal(address(game), 5_000 ether);
        mockVRF.fundSubscription(1, 1_000 ether);
    }

    function test_EnteredLevelQuestIsLiveAtThePromotingRequest() public {
        _driveToLastPurchaseDay();
        Roll memory r = _driveToPromotingRequest();

        // Before consolidation: the request's word is unanswered and the jackpot phase not entered.
        assertTrue(game.rngLocked(), "the promoting request holds the daily lock");
        assertFalse(game.jackpotPhase(), "consolidation has not run");
        (,, bool fulfilled) = mockVRF.pendingRequests(mockVRF.lastRequestId());
        assertFalse(fulfilled, "the promoting request's word is still unanswered");

        assertTrue(r.seen, "the promoting request rolls the level quest");
        assertEq(_activeVersion(), uint256(r.level) + 1, "live version is level + 1");
        assertEq(r.version, r.level + 1, "rolled version is level + 1");
        assertEq(r.questLevel, r.level + 1, "the quest belongs to level + 1");

        uint256 ownPrice = PriceLookupLib.priceForLevel(r.level + 1);
        assertEq(r.target, _targetFor(r.questType, ownPrice), "event target priced at its own level");
        (uint8 viewType,, uint256 viewTarget,,) = quests.getPlayerLevelQuestView(0);
        assertEq(viewType, r.questType, "view shows the rolled type");
        assertEq(viewTarget, r.target, "view target equals the announced target");
    }

    function test_LevelQuestRollsFromTheLastAppliedDailyWord() public {
        _driveToLastPurchaseDay();
        Roll memory r = _driveToPromotingRequest();
        assertTrue(r.seen, "the promoting request rolls the level quest");
        assertTrue(r.priorWord > 1, "a daily word was applied before the request");
        assertEq(r.questType, _expectedType(r.priorWord, r.level), "type = QUEST_LEVEL roll of the prior word");
    }

    // ==================== Oracle ====================

    /// @dev Independent copy of DegenerusQuests._bonusQuestType for the level roll (no primary,
    ///      CRAPS_DAY_PASS tail).
    function _expectedType(uint256 word, uint24 lvl) private view returns (uint8) {
        uint24 next = lvl + 1;
        bool decAllowed = game.decimatorActive()
            && (next % 100 == 0 || (next % 10 == 5 && next % 100 != 95));
        uint8[7] memory types = [MINT_ETH, FLIP, AFFILIATE, DECIMATOR, LOOTBOX, DEGENERETTE_ETH, DEGENERETTE_FLIP];
        uint8[7] memory weights = [1, 4, 1, 4, 3, 1, 1];
        uint256 total = 1;
        for (uint256 i; i < 7; ++i) {
            if (types[i] == DECIMATOR && !decAllowed) continue;
            total += weights[i];
        }
        uint256 roll = EntropyLib.hash2(RngTags.QUEST_LEVEL, word) % total;
        for (uint256 i; i < 7; ++i) {
            if (types[i] == DECIMATOR && !decAllowed) continue;
            if (roll < weights[i]) return types[i];
            roll -= weights[i];
        }
        return CRAPS_DAY_PASS;
    }

    function _targetFor(uint8 t, uint256 price) private pure returns (uint256) {
        if (t == CRAPS_DAY_PASS) return 1;
        if (t == MINT_ETH) return price * 10;
        if (t == LOOTBOX || t == DEGENERETTE_ETH) return price * 20;
        if (t == AFFILIATE) return 6_000;
        return 20_000;
    }

    function _activeVersion() private view returns (uint256) {
        return (uint256(vm.load(ContractAddresses.QUESTS, bytes32(QaSlots.ACTIVE))) >> 136) & 0xffffff;
    }

    // ==================== Drive ====================

    /// @dev From a sealed last-purchase day, crank the next day until the request that moves
    ///      `level`, capturing the word applied before it and the roll event in that transaction.
    function _driveToPromotingRequest() private returns (Roll memory r) {
        uint24 before = game.currentLvl();
        vm.warp(vm.getBlockTimestamp() + 1 days + 1);
        for (uint256 j; j < 60; ++j) {
            vm.recordLogs();
            (bool ok,) = address(game).call(abi.encodeWithSignature("mineRun(uint32)", uint32(0)));
            Vm.Log[] memory logs = vm.getRecordedLogs();
            if (!ok) break;
            if (game.currentLvl() == before + 1) {
                r.level = before + 1;
                // The request moved dailyIdx to d; word d is unanswered, so d - 1's is the latest.
                r.priorWord = game.rngWordForDay(game.currentDayView_g542950() - 1);
                for (uint256 i; i < logs.length; ++i) {
                    if (logs[i].emitter != address(quests) || logs[i].topics[0] != LEVEL_ROLLED) continue;
                    r.seen = true;
                    r.questLevel = uint24(uint256(logs[i].topics[1]));
                    (r.version, r.questType, r.target) = abi.decode(logs[i].data, (uint24, uint8, uint256));
                }
                return r;
            }
            _fulfillVrfIfPending();
        }
        revert("did not reach the promoting request");
    }

    /// @dev Mirrors QuestRetryDoubleRoll._driveToLastPurchaseDay.
    function _driveToLastPurchaseDay() private returns (uint24) {
        uint256 simTime = vm.getBlockTimestamp();
        for (uint256 day = 0; day < 800; day++) {
            require(!game.gameOver(), "gameOver before reaching last-purchase-day");
            (, , bool lpd, bool rngL, ) = game.purchaseInfo_g1027();
            if (game.currentLvl() >= 1 && lpd && !rngL) {
                _settleMidday();
                (, , lpd, rngL, ) = game.purchaseInfo_g1027();
                if (lpd && !rngL) return game.currentLvl();
            }
            simTime += 1 days + 1;
            vm.warp(simTime);
            _seedNextPrizePool(49.9 ether);
            _buyTickets(buyer, 4000);
            for (uint256 j = 0; j < 80; j++) {
                _fulfillVrfIfPending();
                (, , bool lpd2, bool rngL2, ) = game.purchaseInfo_g1027();
                if (game.currentLvl() >= 1 && lpd2 && !rngL2) {
                    _settleMidday();
                    (, , lpd2, rngL2, ) = game.purchaseInfo_g1027();
                    if (lpd2 && !rngL2) return game.currentLvl();
                }
                (bool ok, ) = address(game).call(abi.encodeWithSignature("mineRun(uint32)", uint32(0)));
                if (!ok) break;
            }
        }
        revert("did not reach a last-purchase-day window");
    }

    function _settleMidday() private {
        for (uint256 i; i < 64; i++) {
            if (game.rngLocked()) return;
            uint8 action = game.nextMinerAction();
            if (action == uint8(DegenerusGameStorage.MinerAction.Idle)
                || action == uint8(DegenerusGameStorage.MinerAction.RequestDaily)) return;
            if (action == 2) {
                uint256 id = mockVRF.lastRequestId();
                (,, bool done) = mockVRF.pendingRequests(id);
                if (done) return;
                _fulfillVrfIfPending();
            } else {
                game.mineRun(0);
            }
        }
        revert("harness: mid-day work did not settle");
    }

    function _buyTickets(address who, uint256 qty) private {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo_g1027();
        if (rngLocked_ || game.gameOver()) return;
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;
        if (who.balance < cost) vm.deal(who, cost + 10 ether);
        vm.prank(who);
        try game.purchaseOrderFor{value: cost}(0, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
    }

    function _fulfillVrfIfPending() private {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;
        uint256 randomWord = uint256(keccak256(abi.encode(block.timestamp, game.currentLvl(), reqId)));
        try mockVRF.fulfillRandomWords(reqId, randomWord) {} catch {}
    }

    function _seedNextPrizePool(uint256 targetNext) private {
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
