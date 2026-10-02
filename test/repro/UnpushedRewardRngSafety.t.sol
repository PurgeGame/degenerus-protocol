// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {IDegenerusGameLootboxModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";

/// @dev Seed boundary states only; all opening, publication and request transitions use
///      the deployed production modules. Clean entries represent an already-opened prefix.
contract RewardRngBoundaryFixture is DegenerusGame {
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
        for (uint256 i; i < cleanPrefix; ++i) _subscribers.push(address(uint160(0x100000 + i)));
        _subscribers.push(player);
        _subscriberIndex[player] = _subscribers.length;
        Sub storage sub = _subOf[player];
        sub.amount = 10;
        sub.score = 1200;
        sub.lastAutoBoughtDay = stampDay;
        sub.lastOpenedDay = stampDay - 1;
        _pendingBoxCount = 1;
        _subOpenCursor = 0;
        _subCursor = 0;
        boxCursor = 0;
        _openBountyCarry = 0;
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
        return (uint256(game.extsload(bytes32(uint256(56)))) >> 224) & 0xFFFF;
    }

    function _openedDay() private view returns (uint24) {
        return uint24(uint256(game.extsload(keccak256(abi.encode(PLAYER, uint256(52))))) >> 80);
    }

    function _humanComplete() private view returns (bool) {
        return uint8(uint256(game.extsload(bytes32(uint256(56)))) >> 104) != 0;
    }

    function _expectStampedResolve(uint24 day) private {
        vm.expectCall(
            ContractAddresses.GAME_LOOTBOX_MODULE,
            abi.encodeWithSelector(
                IDegenerusGameLootboxModule.resolveAfkingBox.selector,
                PLAYER, uint256(0.01 ether), day, SESSION_WORD, uint16(1200)
            )
        );
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

        // The clean prefix consumes 1900/1920 units: less than one AFKing open remains,
        // while the empty human queue can finish using the small handed-off remainder.
        game.mineFlip();
        assertTrue(_humanComplete(), "the indexed consumer completed its empty read queue");
        assertEq(_pending(), 1, "weighted walk preserved the final stamped box");
        assertFalse(game.rngComplete(), "the pending AFKing consumer retains the session");

        uint256 requestId = mockVRF.lastRequestId();
        vm.warp(vm.getBlockTimestamp() + 2 days);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.requestLootboxRng();
        assertEq(mockVRF.lastRequestId(), requestId, "no next request while the stamp is pending");
        assertEq(RecyclingState.currentWord(address(game)), SESSION_WORD, "old session remains available");

        // The new-day router drains the final old-session consumer before requesting again.
        _expectStampedResolve(day);
        game.advanceGame();
        assertEq(mockVRF.lastRequestId(), requestId, "final-drain call did not request new entropy");
        assertEq(_pending(), 0);
        assertEq(_openedDay(), day);
        assertTrue(game.rngComplete(), "final AFKing open notifies completion even with human queue already done");
    }

    function test_PreRequestStampCannotUsePreviouslyPublishedWord() public {
        uint24 day = game.currentDayView();
        _seed(day - 1, day, 0, true);
        game.openBoxes(100);
        assertEq(_pending(), 1, "pre-seal stamp remains pending");
        assertEq(_openedDay(), day - 1, "prior published word cannot open a new STAGE stamp");
        assertTrue(game.rngComplete(), "cached prior completion still permits the daily seal");

        uint256 oldRequest = mockVRF.lastRequestId();
        for (uint256 i; i < 32 && mockVRF.lastRequestId() == oldRequest; ++i) game.advanceGame();
        assertGt(mockVRF.lastRequestId(), oldRequest, "new stamps do not deadlock their first request");
        assertFalse(game.rngComplete());
        assertTrue(game.rngLocked());
        game.openBoxes(100);
        assertEq(_pending(), 1, "request lock also retains the stamp");

        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), SESSION_WORD);
        for (uint256 i; i < 256 && game.rngLocked(); ++i) game.advanceGame();
        assertFalse(game.rngLocked(), "daily work reaches unlock");
        _expectStampedResolve(day);
        game.openBoxes(100);
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
        game.openBoxes(100);
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
        for (uint256 i; i < 32 && mockVRF.lastRequestId() == oldRequest; ++i) game.advanceGame();
        assertTrue(game.rngLocked());
        assertGt(mockVRF.lastRequestId(), oldRequest);

        vm.warp(vm.getBlockTimestamp() + 1 days);
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), SESSION_WORD);
        for (uint256 i; i < 256 && game.rngLocked(); ++i) game.advanceGame();
        assertFalse(game.rngLocked(), "delayed request applied and unlocked");
        assertEq(RecyclingState.dailyWord(address(game), stampDay), 0, "gap processing retained only recent daily words");
        assertEq(_pending(), 1, "request-day stamp survived the gap");
        assertFalse(game.rngComplete(), "pending stamp retains the applied active session");

        _expectStampedResolve(stampDay);
        game.openBoxes(100);
        assertEq(_pending(), 0);
        assertEq(_openedDay(), stampDay);
        assertTrue(game.rngComplete());
    }

    function test_NewWriteBoxesDoNotKeepCompletedReadSessionOpen() public {
        uint24 day = game.currentDayView();
        _seed(day, day, 1900, false);
        game.mineFlip();
        _buyWriteBox();
        uint48 write = RecyclingState.writeBuffer(address(game));
        assertGt(uint256(game.extsload(keccak256(abi.encode(write, uint256(57))))), 0);

        _expectStampedResolve(day);
        game.mineFlip();
        assertEq(_pending(), 0);
        assertTrue(game.rngComplete(), "only the sealed read session must finish");
        assertGt(uint256(game.extsload(keccak256(abi.encode(write, uint256(57))))), 0, "new write orders remain queued");
    }

    function test_AfkingDrainAllowsMiddaySessionWithoutReopeningStamp() public {
        uint24 day = game.currentDayView();
        _seed(day, day, 0, false);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.requestLootboxRng();
        game.openBoxes(100);
        assertTrue(game.rngComplete());
        _buyWriteBox();
        vm.prank(address(admin));
        game.creditMiddayRng(PLAYER, 100 ether);
        vm.prank(PLAYER);
        game.requestLootboxRng();
        assertFalse(game.rngComplete());
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xF12345);
        for (uint256 i; i < 256 && !game.rngComplete(); ++i) game.mineFlip();
        assertTrue(game.rngComplete(), "next midday session drains normally");
        assertEq(_pending(), 0);
        assertEq(_openedDay(), day, "completed AFKing stamp is not consumed a second time");
        assertEq(RecyclingState.currentWord(address(game)), 0xF12345);
    }
}
