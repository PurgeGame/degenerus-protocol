// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {QaSlots} from "../helpers/QaSlots.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {QuestInfo} from "../../contracts/interfaces/IDegenerusQuests.sol";

/// @dev Shared full-protocol drive: real purchases, real daily requests, words held back.
abstract contract QuestRequestDrive is DeployProtocol {
    uint8 internal constant MINT_ETH = 1;
    uint8 internal constant FOIL = 4;
    uint8 internal constant LOOTBOX = 6;

    uint256 internal _t;
    uint256 internal _nonce;
    address internal p;

    function _fulfilLatest(uint256 w) internal {
        uint256 req = mockVRF.lastRequestId();
        if (req == 0) return;
        (,, bool done) = mockVRF.pendingRequests(req);
        if (!done) mockVRF.fulfillRandomWords(req, w);
    }

    /// @dev Finish everything owed for the current logical day.
    function _settle() internal {
        for (uint256 i; i < 400; ++i) {
            _fulfilLatest(uint256(keccak256(abi.encode("live-req", _nonce++))) | 1);
            if (!game.advanceDue() && !game.rngLocked()) break;
            try game.mineRun(0) {} catch {}
        }
        _mineAll(64);
    }

    /// @dev Cross the next reset and run the chain until the fresh daily request is in flight.
    function _toRequest() internal returns (uint24 day) {
        uint24 before = game.currentDayView_g542950();
        _t += 1 days;
        vm.warp(_t);
        for (uint256 i; i < 400 && game.currentDayView_g542950() == before; ++i) {
            _fulfilLatest(uint256(keccak256(abi.encode("live-req-pre", _nonce++))) | 1);
            if (game.currentDayView_g542950() != before) break;
            try game.mineRun(0) {} catch {}
        }
        day = game.currentDayView_g542950();
        assertEq(day, before + 1, "one fresh daily request");
        assertTrue(game.rngLocked(), "the daily request is in flight");
        (,, bool done) = mockVRF.pendingRequests(mockVRF.lastRequestId());
        assertFalse(done, "its word is not delivered");
    }

    /// @dev One ticket plus a 0.5 ETH box: MINT_ETH and LOOTBOX progress, level MINT_ETH progress.
    function _buy() internal {
        (,,,, uint256 priceWei) = game.purchaseInfo_g1027();
        uint256 box = 0.5 ether;
        vm.prank(p);
        game.purchaseOrderFor{value: priceWei + box}(
            0, 400, BoxOrderLib.boCustomFloor(box), bytes32(0), MintPaymentKind.DirectEth, false
        );
    }
}

/// @notice Daily quests roll at the daily request from the last applied daily word, so the
///         requested day's quests are live, and credit progress, before its word arrives.
contract QuestLiveAtRequest is QuestRequestDrive {
    uint32 private id;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 1_000 ether);
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
        _finishSubscriptionWindow();
        p = makeAddr("live_at_request_player");
        vm.deal(p, 1_000 ether);
    }

    function _levelWord() private view returns (uint256) {
        return uint256(vm.load(ContractAddresses.QUESTS, keccak256(abi.encode(uint256(id), QaSlots.LEVEL))));
    }

    function test_QuestsAreLiveAtTheRequest() public {
        _settle();
        uint24 d = _toRequest();
        QuestInfo[2] memory q = quests.getActiveQuests();
        assertEq(q[0].day, d, "slot 0 belongs to the requested day");
        assertEq(q[1].day, d, "slot 1 belongs to the requested day");
        assertEq(q[0].questType, MINT_ETH, "slot 0 is MINT_ETH");
        assertEq(uint24(uint256(vm.load(ContractAddresses.QUESTS, bytes32(QaSlots.ACTIVE)))), d, "stored day");
    }

    function test_ProgressBetweenRequestAndWordCounts() public {
        _settle();
        _buy();
        id = game.walletIdOf_g3120(p);
        _settle();
        uint24 d = _toRequest();

        (uint8 lqType,,, bool lqDone,) = quests.getPlayerLevelQuestView(id);
        assertEq(lqType, MINT_ETH, "fixture: the seeded level quest is MINT_ETH");
        assertFalse(lqDone, "fixture: not yet eligible, so the level quest keeps accumulating");
        uint256 before = uint128(_levelWord() >> 24);
        (bool slot0Before,) = quests.questCompletionToday(id);
        assertFalse(slot0Before, "the requested day starts with nothing completed");

        _buy();

        (bool slot0,) = quests.questCompletionToday(id);
        assertTrue(slot0, "a buy before the word completes the requested day's primary");
        assertGt(uint128(_levelWord() >> 24), before, "a buy before the word adds level-quest progress");
        QuestInfo[2] memory q = quests.getActiveQuests();
        assertEq(q[0].day, d, "credited on the requested day");
    }
}

/// @notice The first two days have no prior word: slot 1 is FOIL on the deploy day and LOOTBOX on
///         the next. The test fixture deploys on a later day index than production's day 1.
contract QuestGenesisDaysFixed is QuestRequestDrive {
    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 1_000 ether);
        _t = block.timestamp;
        vm.deal(address(game), 5_000_000 ether);
        p = makeAddr("genesis_days_player");
        vm.deal(p, 1_000 ether);
    }

    function test_DayOneFoilDayTwoLootbox() public {
        uint24 day0 = uint24(game.currentDayView_g542950());
        QuestInfo[2] memory q = quests.getActiveQuests();
        assertEq(q[1].day, day0, "the seeded pair belongs to the deploy day");
        assertEq(q[0].questType, MINT_ETH, "day 1 slot 0");
        assertEq(q[1].questType, FOIL, "day 1 slot 1 is FOIL");

        uint24 d = _toRequest();
        assertEq(d, day0 + 1, "day 2's request");
        q = quests.getActiveQuests();
        assertEq(q[1].day, d, "day 2's pair is live at its request");
        assertEq(q[0].questType, MINT_ETH, "day 2 slot 0");
        assertEq(q[1].questType, LOOTBOX, "day 2 slot 1 is LOOTBOX");

        // Completable on day 2: one buy clears the primary, then the box clears LOOTBOX.
        _buy();
        (bool slot0, bool slot1) = quests.questCompletionToday(game.walletIdOf_g3120(p));
        assertTrue(slot0, "day 2 primary completes");
        assertTrue(slot1, "day 2 LOOTBOX completes");
    }
}
