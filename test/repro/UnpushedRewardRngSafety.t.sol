// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {IDegenerusGameLootboxModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @dev Seed boundary states only; all opening, publication and request transitions use
///      the deployed production modules. Clean entries represent an already-opened prefix.
contract RewardRngBoundaryFixture is DegenerusGame, WalletSeed {
    function seedStampedRead(
        address player, uint24 sealedDay, uint24 stampDay, uint256 word, uint256 cleanPrefix, bool complete
    ) external {
        dailyIdx = sealedDay;
        rngLockedFlag = false;
        rngWordCurrent = word;
        _setRngRequestActive(false);
        _setRngSessionPublished(true);
        _setRngComplete(complete);
        ticketsFullyProcessed = true;
        humanReadComplete = complete;
        _recordDailyRng(sealedDay, word);
        delete _subscribers;
        for (uint256 i; i < cleanPrefix; ++i) {
            address member = address(uint160(0x100000 + i));
            uint32 memberId = _seedWallet(member);
            _subscribers.push(uint256(uint160(member)) | (uint256(memberId) << 160));
            _subOf[memberId].setPosition = uint32(_subscribers.length);
        }
        uint32 subId = _seedWallet(player);
        _subscribers.push(uint256(uint160(player)) | (uint256(subId) << 160));
        _subOf[subId].setPosition = uint32(_subscribers.length);
        Sub storage sub = _subOf[subId];
        sub.amount = 10;
        sub.score = 1200;
        sub.lastAutoBoughtDay = stampDay;
        sub.lastOpenedDay = stampDay - 1;
        _pendingBoxCount = 1;
        _subOpenCursor = 0;
        _subCursor = 0;
        boxCursor = 0;
    }
}

contract UnpushedRewardRngSafetyTest is DeployProtocol {
    address private constant PLAYER = address(0xB0A);
    uint256 private constant SESSION_WORD = 0xC0FFEE;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 5 days);
        vm.deal(address(game), 5000 ether);
        vm.deal(PLAYER, 100 ether);
        mockVRF.fundSubscription(1, 1000 ether);
        vm.fee(0);
    }

    function _seed(uint24 sealedDay, uint24 stampDay, uint256 cleanPrefix, bool complete) private {
        bytes memory original = address(game).code;
        vm.etch(address(game), type(RewardRngBoundaryFixture).runtimeCode);
        RewardRngBoundaryFixture(payable(address(game))).seedStampedRead(
            PLAYER, sealedDay, stampDay, SESSION_WORD, cleanPrefix, complete
        );
        vm.etch(address(game), original);
    }

    function _pending() private view returns (uint256) {
        return (uint256(game.extsload(bytes32(GameSlots.PENDING_BOX_COUNT))) >> (GameSlots.PENDING_BOX_COUNT_OFFSET * 8)) & 0xFFFF;
    }

    function _openedDay() private view returns (uint24) {
        return uint24(uint256(game.extsload(keccak256(abi.encode(uint256(game.walletIdOf(PLAYER)), GameSlots.SUB_OF)))) >> 80);
    }

    function _humanComplete() private view returns (bool) {
        return uint8(uint256(game.extsload(bytes32(GameSlots.SUB_CURSOR))) >> 104) != 0;
    }

    function _expectStampedResolve(uint24 day) private {
        vm.expectCall(
            ContractAddresses.GAME_LOOTBOX_MODULE,
            abi.encodeWithSelector(
                IDegenerusGameLootboxModule.resolveAfkingBox.selector,
                PLAYER, game.walletIdOf(PLAYER), uint256(0.01 ether), day, SESSION_WORD, uint16(1200)
            )
        );
    }

    /// @dev One keeper call at a 2M allowance. The engine admits work by declared gas bounds
    ///      (60d31f775): the AFKing scan admits one entry per AFKING_SKIP_GAS/AFKING_OPEN_GAS, so
    ///      a bounded call walks a bounded prefix, and 2M can never admit a fresh request
    ///      (RNG_REQUEST plus tail), so the session under test is never sealed behind the test.
    function _keep() private {
        game.mineFlip{gas: 2_000_000}();
    }

    function _buyWriteBox() private {
        vm.prank(PLAYER);
        game.purchase{value: 1 ether}(
            PLAYER, 0, BoxOrderLib.boCustom(1 ether), bytes32(0), MintPaymentKind.DirectEth, false
        );
    }

    function test_PartialAfkingScanCannotCompleteSessionThroughEmptyHumanQueue() public {
        uint24 day = game.currentDayView();
        _seed(day, day, 1900, false);

        // A bounded keeper call walks only part of the 1900-entry clean prefix: the final
        // stamped box stays pending. The shared consumer order (60d31f775) runs human boxes only
        // after AFKing finishes, so the empty human queue cannot complete the session early.
        _keep();
        assertFalse(_humanComplete(), "the indexed consumer completed its empty read queue");
        assertEq(_pending(), 1, "weighted walk preserved the final stamped box");
        assertFalse(game.rngComplete(), "the pending AFKing consumer retains the session");

        uint256 requestId = mockVRF.lastRequestId();
        vm.warp(vm.getBlockTimestamp() + 2 days);
        // The pending AFKing consumer, not a fresh request, is the engine's next work.
        assertEq(game.nextMinerAction(), 9, "no next request while the stamp is pending"); // Afking
        assertEq(mockVRF.lastRequestId(), requestId, "no next request while the stamp is pending");
        assertEq(RecyclingState.currentWord(address(game)), SESSION_WORD, "old session remains available");

        // The new-day router drains the final old-session consumer before requesting again.
        _expectStampedResolve(day);
        for (uint256 i; i < 64 && _pending() != 0; ++i) _keep();
        assertEq(mockVRF.lastRequestId(), requestId, "final-drain call did not request new entropy");
        assertEq(_pending(), 0);
        assertEq(_openedDay(), day);
        assertTrue(_humanComplete(), "the empty human queue completes after AFKing");
        assertTrue(game.rngComplete(), "final AFKing open notifies completion even with human queue already done");
    }

    function test_PreRequestStampCannotUsePreviouslyPublishedWord() public {
        uint24 day = game.currentDayView();
        _seed(day - 1, day, 0, true);
        assertEq(_pending(), 1, "pre-seal stamp remains pending");
        assertTrue(game.rngComplete(), "cached prior completion still permits the daily seal");
        // The completed session offers the new stamp no AFKing stage on the prior published word.
        assertTrue(game.nextMinerAction() != 9, "prior published word cannot open a new STAGE stamp"); // Afking

        uint256 oldRequest = mockVRF.lastRequestId();
        for (uint256 i; i < 32 && mockVRF.lastRequestId() == oldRequest; ++i) game.mineFlip();
        assertGt(mockVRF.lastRequestId(), oldRequest, "new stamps do not deadlock their first request");
        assertEq(_openedDay(), day - 1, "prior published word cannot open a new STAGE stamp");
        assertFalse(game.rngComplete());
        assertTrue(game.rngLocked());
        // Under the request lock the engine only waits for the word.
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.mineFlip();
        assertEq(_pending(), 1, "request lock also retains the stamp");

        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), SESSION_WORD);
        // The new session's read consumers run right after the unlock, in the keeper's own flow
        // (60d31f775); the stamp must resolve on the NEW word with its own day, whoever opens it.
        _expectStampedResolve(day);
        for (uint256 i; i < 256 && game.rngLocked(); ++i) game.mineFlip();
        assertFalse(game.rngLocked(), "daily work reaches unlock");
        _mineAll(64);
        assertEq(_pending(), 0);
        assertEq(_openedDay(), day);
    }

    function test_DelayedStampUsesActiveSessionAfterDailyParityReuse() public {
        uint24 day = game.currentDayView();
        uint24 stampDay = day - 3;
        _seed(day, stampDay, 0, false);
        RecyclingState.seedDailyWord(address(game), stampDay, 0xBAD);
        RecyclingState.seedDailyWord(address(game), stampDay + 2, 0xBADBEEF);
        assertEq(RecyclingState.dailyWord(address(game), stampDay), 0, "old daily cache entry was recycled");

        _expectStampedResolve(stampDay);
        game.mineFlip();
        assertEq(_pending(), 0, "delayed fulfillment needs no retained stamp-day word");
        assertEq(_openedDay(), stampDay, "frozen day remains the reward domain input");
        assertTrue(game.rngComplete());
    }

    function test_DelayedDailyFulfillmentRetainsOriginalStampWithActiveWord() public {
        uint24 stampDay = game.currentDayView();
        _seed(stampDay - 1, stampDay, 0, true);
        // A chunked pre-request STAGE can resume days after it stamped this subscriber.
        // The no-orphan rule retains the stamp while the eventual request binds its own day.
        vm.warp(vm.getBlockTimestamp() + 3 days);
        uint256 oldRequest = mockVRF.lastRequestId();
        for (uint256 i; i < 32 && mockVRF.lastRequestId() == oldRequest; ++i) game.mineFlip();
        assertTrue(game.rngLocked());
        assertGt(mockVRF.lastRequestId(), oldRequest);

        uint24 requestDay = game.currentDayView();
        uint256 delivered = mockVRF.lastRequestId();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        mockVRF.fulfillRandomWords(delivered, SESSION_WORD);
        // The stamp must survive the gap (the no-orphan rule keeps it through the multi-day
        // request) and resolve on the active session word with its ORIGINAL stamp day. Its open
        // now runs in the keeper's own consumer order right after the unlock (60d31f775), so the
        // resolve is expected across the drain rather than at a separate helper call. The call
        // that seals the delayed day may continue into the next wall day's request, so the drive
        // stops on the seal.
        _expectStampedResolve(stampDay);
        vm.recordLogs();
        for (uint256 i; i < 256 && _dailyIdx() < requestDay; ++i) game.mineFlip();
        assertEq(_dailyIdx(), requestDay, "delayed request applied and unlocked");
        assertEq(RecyclingState.dailyWord(address(game), stampDay), 0, "gap processing retained only recent daily words");
        _mineAll(64);
        assertEq(_pending(), 0, "request-day stamp survived the gap");
        // The same composed call may go on to prepare the next wall day's subscriptions, where
        // this unfunded fixture subscription expires (its record is deleted); otherwise the
        // record must show the stamp opened with its original day.
        if (_openedDay() != stampDay) {
            Vm.Log[] memory logs = vm.getRecordedLogs();
            bool expired;
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics.length > 1 && logs[i].topics[0] == keccak256("SubscriptionExpired(address,uint8)")
                    && address(uint160(uint256(logs[i].topics[1]))) == PLAYER) expired = true;
            }
            assertTrue(expired, "opened with its stamp day, or expired afterwards");
        }
        // Completion was certified: either the session still reads complete, or the next wall
        // day's request was sealed, which the read-complete gate permits only after it.
        assertTrue(game.rngComplete() || mockVRF.lastRequestId() > delivered, "the session completed");
    }

    function _dailyIdx() private view returns (uint24) {
        return uint24(uint256(game.extsload(bytes32(0))) >> 24);
    }

    function test_NewWriteBoxesDoNotKeepCompletedReadSessionOpen() public {
        uint24 day = game.currentDayView();
        _seed(day, day, 1900, false);
        _keep();
        _buyWriteBox();
        uint48 write = RecyclingState.writeBuffer(address(game));
        assertGt(uint256(game.extsload(keccak256(abi.encode(write, GameSlots.BOX_PLAYERS)))), 0);

        _expectStampedResolve(day);
        for (uint256 i; i < 64 && _pending() != 0; ++i) _keep();
        assertEq(_pending(), 0);
        assertTrue(game.rngComplete(), "only the sealed read session must finish");
        assertGt(uint256(game.extsload(keccak256(abi.encode(write, GameSlots.BOX_PLAYERS)))), 0, "new write orders remain queued");
    }

    function test_AfkingDrainAllowsMiddaySessionWithoutReopeningStamp() public {
        uint24 day = game.currentDayView();
        // setUp's 5-day jump leaves scheduled Craps maintenance owed, which also refuses a
        // mid-day request (RngModule: _minerMaintenancePending). Run it through the table's own
        // permissionless keeper first (it runs only between read sessions), so the refusals and
        // the request below answer to the AFKing read session alone.
        _quietCrapsTable();
        _seed(day, day, 0, false);
        // The pending AFKing consumer, not a mid-day request, is the engine's next work.
        assertEq(game.nextMinerAction(), 9, "no mid-day request while the AFKing stamp is pending"); // Afking
        game.mineFlip();
        assertTrue(game.rngComplete());
        _buyWriteBox();
        vm.prank(address(admin));
        game.creditMiddayRng(PLAYER, 100 ether);
        vm.prank(PLAYER);
        uint8 next = game.minerAction();
        assertEq(next, 18, "the drained session admits the donor's mid-day request"); // RequestMidday
        vm.prank(PLAYER);
        game.mineFlip();
        assertFalse(game.rngComplete());
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xF12345);
        for (uint256 i; i < 256 && !game.rngComplete(); ++i) game.mineFlip();
        assertTrue(game.rngComplete(), "next midday session drains normally");
        assertEq(_pending(), 0);
        assertEq(_openedDay(), day, "completed AFKing stamp is not consumed a second time");
        assertEq(RecyclingState.currentWord(address(game)), 0xF12345);
    }
}
