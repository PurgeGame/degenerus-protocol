// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {LogicalDaysFixture} from "./helpers/LogicalDaysFixture.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @notice Transport replacement, late visibility, input commitment and exact timeout origins.
contract VRFStallEdgeCases is LogicalDaysFixture {
    function _requestAtNextReset() private returns (uint256) {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        return _requestLogical();
    }
    function test_CoordinatorSwapPreservesDayCohortAndProgressOrigin() public {
        uint256 old = _requestAtNextReset();
        bytes32 requestHeader = vm.load(address(game), bytes32(0));
        (bool complete,uint24 sent,uint48 completed) = game.dailySessionState();
        vm.warp(vm.getBlockTimestamp() + 4 days);
        MockVRFCoordinator replacement = _rotateLogical();
        bytes32 afterHeader = vm.load(address(game), bytes32(0));
        uint256 identityMask = (uint256(type(uint48).max) << 48) | (uint256(type(uint24).max) << 24) | (uint256(1) << 252);
        assertEq(uint256(requestHeader) & identityMask, uint256(afterHeader) & identityMask);
        (bool afterComplete,uint24 afterSent,uint48 afterCompleted) = game.dailySessionState();
        assertEq(afterComplete, complete);
        assertEq(afterSent, sent);
        assertEq(afterCompleted, completed);
        assertEq(coinflip.requestedDailyIdx(), 2);
        vm.expectRevert();
        mockVRF.fulfillRandomWords(old, 777);
        replacement.fulfillRandomWords(replacement.lastRequestId(), 0xBEEF);
        vm.expectCall(address(coinflip), abi.encodeCall(coinflip.processCoinflipPayouts,
            (uint8(2), uint256(0xBEEF), uint24(2))));
        _finishLogical();
        assertEq(game.rngWordForDay(2), 0xBEEF);
        assertLe(game.currentDayView_g542950(), 3);
    }
    function test_RetryKeepsCommitmentAndCannotRefreshHardDeadline() public {
        _requestAtNextReset();
        uint256 header = uint256(vm.load(address(game), bytes32(0)));
        (,,uint48 completed) = game.dailySessionState();
        vm.warp(vm.getBlockTimestamp() + 21 hours);
        vm.prank(address(admin));
        game.retryRng();
        uint256 afterHeader = uint256(vm.load(address(game), bytes32(0)));
        assertEq(uint48(afterHeader >> 48), uint48(header >> 48));
        assertEq(uint24(afterHeader >> 24), 2);
        (,,uint48 afterCompleted) = game.dailySessionState();
        assertEq(afterCompleted, completed);
        vm.warp(uint256(completed) + 14 days);
        assertTrue(game.livenessTriggered());
        assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.Terminal));
    }
    function test_RefusedRequestRollsBackMirrorsAndPacing() public {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        // Preparation is independently checkpointed. Force a refusal only after it is complete.
        vm.mockCallRevert(address(mockVRF), abi.encodeWithSelector(mockVRF.requestRandomWords.selector), abi.encodeWithSignature("Refused()"));
        for (uint256 i; i < 20 && game.nextMinerAction() != uint8(DegenerusGameStorage.MinerAction.RequestDaily); ++i) {
            (bool ok,) = address(game).call(abi.encodeWithSignature("mineRun(uint32)", uint32(0)));
            if (!ok) break;
        }
        uint24 beforeDay = game.currentDayView_g542950();
        (bool complete,uint24 sent,uint48 completed) = game.dailySessionState();
        bytes32 mirror = vm.load(address(coinflip), bytes32(uint256(4)));
        bytes32 commitment = vm.load(address(game), bytes32(0));
        (bool accepted,) = address(game).call(abi.encodeWithSignature("mineRun(uint32)", uint32(0)));
        assertTrue(accepted, "coordinator refusal is a non-reverting uncharged no-op");
        assertEq(game.currentDayView_g542950(), beforeDay);
        assertEq(vm.load(address(coinflip), bytes32(uint256(4))), mirror);
        assertEq(vm.load(address(game), bytes32(0)), commitment);
        (bool ac,uint24 as_,uint48 at) = game.dailySessionState();
        assertEq(ac, complete); assertEq(as_, sent); assertEq(at, completed);
        vm.clearMockedCalls();
        _requestLogical();
        assertEq(game.currentDayView_g542950(), beforeDay + 1);
        assertEq(coinflip.requestedDailyIdx(), beforeDay + 1);
    }
    function test_KnownWordCannotRepriceCarryAndNewDepositTargetsFollowingRound() public {
        address player = address(0xA11CE);
        uint32 id = _giveWalletId(player);
        vm.prank(ContractAddresses.GAME); coin.mintForGame_g152734(player, 100_000);
        vm.prank(player); coinflip.playCoinflip(id, 1_000);
        uint256 request = _requestAtNextReset();
        mockVRF.fulfillRandomWords(request, 777);
        vm.prank(player); coinflip.playCoinflip(id, 2_000);
        assertEq(coinflip.requestedDailyIdx(), 2);
        _finishLogical();
        (uint16 reward,) = coinflip.getCoinflipDayResult(3);
        assertEq(reward, 0);
    }
    function test_MiddaySessionDoesNotAdvanceDayOrCertifyDailyProgress() public {
        // A normal post-Degenesis purchase supplies a real midday box cohort.
        for (uint256 d = 2; d <= 9; ++d) _nextLogical(777 + d);
        // Finish any automatically requested midday maintenance before adding this cohort.
        for (uint256 i; i < 200 && uint8(game.nextMinerAction()) != 0; ++i) {
            uint256 pending = mockVRF.lastRequestId();
            if (pending != 0) {
                (,,bool delivered) = mockVRF.pendingRequests(pending);
                if (!delivered) mockVRF.fulfillRandomWords(pending, 777);
            }
            game.mineRun(type(uint32).max);
        }
        (,,uint48 completed) = game.dailySessionState();
        uint24 day = game.currentDayView_g542950();
        address buyer = address(0xB0B);
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        game.purchaseOrderFor{value: 1.01 ether}(0, 400, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        uint256 old = mockVRF.lastRequestId();
        for (uint256 i; i < 100 && mockVRF.lastRequestId() == old; ++i) game.mineRun(0);
        assertGt(mockVRF.lastRequestId(), old);
        assertFalse(game.rngLocked());
        assertEq(game.currentDayView_g542950(), day);
        vm.warp(vm.getBlockTimestamp() + 1 hours);
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 1234);
        _finishReadConsumers();
        (,,uint48 later) = game.dailySessionState();
        assertEq(later, completed);
        assertEq(coinflip.requestedDailyIdx(), day);
    }
    function testFuzz_CoordinatorSwapPreservesNudges(uint8 count) public {
        count = uint8(bound(count, 1, 3));
        address buyer = address(0xB0B);
        _giveWalletId(buyer);
        vm.prank(ContractAddresses.GAME); coin.mintForGame_g152734(buyer, 100_000_000);
        for (uint256 i; i < count; ++i) {
            (,uint256 cost) = game.rngNudgeQuote();
            vm.prank(buyer); game.reverseFlip(cost);
        }
        _requestAtNextReset();
        uint256 nudges = RecyclingState.nudgeCount(address(game));
        _rotateLogical();
        assertEq(RecyclingState.nudgeCount(address(game)), nudges);
        assertEq(game.currentDayView_g542950(), 2);
    }
}
