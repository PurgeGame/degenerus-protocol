// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenesisDeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {RngTags} from "../../contracts/libraries/RngTags.sol";

contract LogicalDayHeaders is DegenerusGameStorage {
    function setPurchase(uint24 day, uint24 baseline, bool complete, uint48 completedAt) external {
        dailyIdx = day;
        purchaseStartDay = baseline;
        dailyComplete = complete;
        lastDailyCompletedAt = completedAt;
        lastDailyRequestWallDay = _wallDay();
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        _setPrizePools(0, 0);
        _setRngComplete(complete);
    }
    function publish() external { _setRngSessionPublished(true); }
    function blockLaterConsumers() external {
        rngLockedFlag = false;
        _clearRngRequest();
        _setRngSessionPublished(true);
        ticketsFullyProcessed = true;
        humanReadComplete = false;
    }
    function latchPreparation() external {
        _afkingResetDay = dailyIdx + 1;
        subsFullyProcessed = false;
        _subCursor = 1;
    }
    function certify() external { _certifyRngComplete(); }
    function reserveClaims(uint32 id, uint128 claim, uint128 afking) external {
        balancesPacked[id] = uint256(claim + 1) | (uint256(afking) << 128);
        claimablePool += claim + afking;
    }
}

contract LogicalGameDaysTest is DegenesisDeployProtocol {
    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 1_000 ether);
    }

    function _fixture(bytes memory callData) internal {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(LogicalDayHeaders).runtimeCode);
        (bool ok, bytes memory result) = address(game).call(callData);
        vm.etch(address(game), code);
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
    }

    function _request() internal returns (uint256) {
        for (uint256 i; i < 100; ++i) {
            if (game.rngLocked()) return mockVRF.lastRequestId();
            game.mineRun(0);
        }
        revert("daily request did not commit");
    }

    function _finishDaily() internal {
        for (uint256 i; i < 500; ++i) {
            (bool complete,,) = game.dailySessionState();
            if (complete) return;
            game.mineRun(0);
        }
        revert("daily consumers did not complete");
    }

    function test_LevelOneDailySealCompletesAtMaximumMultiplier() public {
        for (uint24 day = 2; day <= 9; ++day) {
            vm.warp(vm.getBlockTimestamp() + 1 days);
            mockVRF.fulfillRandomWords(_request(), 777);
            for (uint256 call; call < 200; ++call) {
                (bool complete,,) = game.dailySessionState();
                if (complete) break;
                game.mineRun{gas: 16_700_000}(type(uint32).max);
            }
            (bool complete,,) = game.dailySessionState();
            assertTrue(complete, "mandatory phase includes its complete sealing tail");
            assertEq(game.currentDayView_g542950(), day);
        }
    }

    function test_BootstrapAndRequestOwnLogicalDay() public {
        assertEq(game.currentDayView_g542950(), 1);
        assertEq(coinflip.requestedDailyIdx(), 1);
        (uint16 first,) = coinflip.getCoinflipDayResult(1);
        assertEq(first, 0, "opening day has no phantom flip");
        vm.warp(block.timestamp + 8 days);
        assertEq(game.currentDayView_g542950(), 1, "calendar creates no rounds");
        uint256 request = _request();
        assertEq(game.currentDayView_g542950(), 2);
        assertEq(coinflip.requestedDailyIdx(), 2);
        (bool complete, uint24 wall, uint48 completedAt) = game.dailySessionState();
        assertFalse(complete);
        assertEq(wall, game.currentWallDayView());
        assertLt(completedAt, block.timestamp);
        mockVRF.fulfillRandomWords(request, 777);
        assertEq(game.currentDayView_g542950(), 2, "callback cannot increment");
        _finishDaily();
        (complete,, completedAt) = game.dailySessionState();
        assertTrue(complete);
        assertEq(completedAt, block.timestamp);
        assertEq(game.currentDayView_g542950(), 2);
        assertEq(game.latestDailyResultDay(), 2);
        (uint16 nonexistent,) = coinflip.getCoinflipDayResult(3);
        assertEq(nonexistent, 0);
        assertFalse(game.advanceDue(), "no second allowance in actual send window");
    }

    function test_CompletionCertificateExactlyOnce() public {
        vm.warp(block.timestamp + 1 days);
        mockVRF.fulfillRandomWords(_request(), 777);
        _finishDaily();
        (,,uint48 completed) = game.dailySessionState();
        vm.warp(block.timestamp + 1 hours);
        _fixture(abi.encodeCall(LogicalDayHeaders.certify, ()));
        (,,uint48 repeated) = game.dailySessionState();
        assertEq(repeated, completed);
    }

    function test_PreparationKeepsNextLogicalIdentityAcrossResets() public {
        vm.warp(block.timestamp + 1 days);
        _fixture(abi.encodeCall(LogicalDayHeaders.latchPreparation, ()));
        vm.warp(block.timestamp + 3 days);
        _request();
        assertEq(game.currentDayView_g542950(), 2);
        (,uint24 wall,) = game.dailySessionState();
        assertEq(wall, game.currentWallDayView());
    }

    function test_ThirtyCompletedPurchaseDaysAndNextResetPrecedence() public {
        uint48 nowTs = uint48(block.timestamp);
        _fixture(abi.encodeCall(LogicalDayHeaders.setPurchase, (uint24(38), uint24(9), true, nowTs)));
        vm.warp(uint256(nowTs) + 1 days);
        assertFalse(game.livenessTriggered(), "29 complete days");
        _fixture(abi.encodeCall(LogicalDayHeaders.setPurchase, (uint24(39), uint24(9), false, uint48(vm.getBlockTimestamp()))));
        vm.warp(uint256(nowTs) + 2 days);
        assertFalse(game.livenessTriggered(), "pending thirtieth day does not count");
        _fixture(abi.encodeCall(LogicalDayHeaders.setPurchase, (uint24(39), uint24(9), true, uint48(vm.getBlockTimestamp()))));
        assertFalse(game.livenessTriggered(), "late completion gets its own open window");
        vm.warp(uint256(nowTs) + 3 days);
        assertTrue(game.livenessTriggered(), "completed thirtieth day must end on next reset");
        assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.Terminal));
    }

    function _hardEnding(uint8 stuck) internal {
        uint256 initial = 123 ether;
        vm.deal(address(game), 73 ether);
        mockStETH.mint(address(game), 50 ether);
        address claimant = address(0xA11CE);
        uint32 claimantId = _giveWalletId(claimant);
        address stakedHolder = address(0x5D61111);
        address wrappedHolder = address(0xD61111);
        uint256 shares = dgnrs.balanceOf(ContractAddresses.VAULT) / 100;
        _unwrapFromVault(stakedHolder, shares);
        _dgnrsFromVault(wrappedHolder, shares);
        if (stuck > 0 && stuck < 5) {
            vm.warp(block.timestamp + 1 days);
            uint256 request = _request();
            if (stuck >= 2) mockVRF.fulfillRandomWords(request, 777);
            if (stuck == 3) _fixture(abi.encodeCall(LogicalDayHeaders.publish, ()));
            if (stuck == 4) _fixture(abi.encodeCall(LogicalDayHeaders.blockLaterConsumers, ()));
        } else if (stuck == 0) {
            _fixture(abi.encodeCall(LogicalDayHeaders.latchPreparation, ()));
        } else {
            _fixture(abi.encodeCall(LogicalDayHeaders.setPurchase, (uint24(39), uint24(9), true, uint48(block.timestamp))));
        }
        _fixture(abi.encodeCall(LogicalDayHeaders.reserveClaims, (claimantId, uint128(7 ether), uint128(5 ether))));
        (,,uint48 completed) = game.dailySessionState();
        vm.warp(uint256(completed) + (stuck < 5 ? 14 days : 1 days));
        // Exercise the newly admitted trigger-to-closure window in all seven exits.
        _syncCoinflipFixtureDay(game.currentDayView_g542950());
        address late = address(0x1A7E);
        uint32 lateId = _giveWalletId(late);
        vm.prank(address(game)); coin.mintForGame_g152734(late, 200_000);
        uint256 rewardPool = sdgnrs.poolBalance(sDGNRS.Pool.Reward);
        uint256 shareSupply = sdgnrs.totalSupply();
        assertTrue(game.livenessTriggered());
        vm.prank(late); coinflip.playCoinflip(lateId, 200_000);
        assertEq(coin.balanceOf(late), 0);
        assertGe(coinflip.coinflipAmountById(lateId), 200_000);
        uint256 lateShares = sdgnrs.balanceOf(late);
        assertGt(lateShares, 0, "record-sized late deposit exercises real sDGNRS reward");
        assertEq(sdgnrs.totalSupply(), shareSupply, "reward transfers existing shares");
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Reward) + lateShares, rewardPool);
        assertEq(address(game).balance + mockStETH.balanceOf(address(game)), initial);
        assertEq(sdgnrs.balanceOf(stakedHolder), shares);
        assertEq(dgnrs.balanceOf(wrappedHolder), shares);
        if (stuck == 6) {
            bytes memory requestSelector = abi.encodeWithSelector(mockVRF.requestRandomWords.selector);
            vm.mockCallRevert(address(mockVRF), requestSelector, abi.encodeWithSignature("CoordinatorRefused()"));
            vm.expectCall(address(mockVRF), requestSelector);
            for (uint256 i; i < 5; ++i) {
                // Refused coordinator calls may report waiting or roll back the attempt.
                (bool ok,) = address(game).call(abi.encodeWithSignature("mineRun(uint32)", uint32(0)));
                ok;
            }
            assertEq(mockVRF.lastRequestId(), 0, "the coordinator never accepted the terminal request");
            assertFalse(game.gameOver(), "normal ending still waits for unavailable entropy");
            vm.warp(uint256(completed) + 14 days);
        }
        assertTrue(game.livenessTriggered(), "ending takes precedence");
        assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.Terminal));
        // Refuse normal workers. The terminal route must bypass all of them.
        vm.mockCallRevert(ContractAddresses.GAME_AFKING_MODULE,
            abi.encodeWithSignature("runSubscriberWork_g6352(uint24,uint256)"), abi.encodeWithSignature("BrokenNormalWorker()"));
        vm.mockCallRevert(ContractAddresses.GAME_TICKET_MODULE,
            abi.encodeWithSignature("runTicketWork_g1150(uint24,uint256)"), abi.encodeWithSignature("BrokenNormalWorker()"));
        vm.mockCallRevert(ContractAddresses.CRAPS,
            abi.encodeWithSignature("runDailyBattleWork(uint256)"), abi.encodeWithSignature("BrokenNormalWorker()"));
        for (uint256 i; i < 500 && game.gameOverTimestamp() == 0; ++i) {
            if (stuck == 5) {
                uint256 request = mockVRF.lastRequestId();
                if (request != 0) {
                    (,, bool fulfilled) = mockVRF.pendingRequests(request);
                    if (!fulfilled) mockVRF.fulfillRandomWords(request, 777);
                }
            }
            game.mineRun(0);
        }
        assertTrue(game.gameOver());
        assertGt(game.gameOverTimestamp(), 0);
        assertEq(address(game).balance + mockStETH.balanceOf(address(game)), initial,
            "terminal accounting preserves every funded wei before pull claims/sweep");
        uint256 paidBefore = claimant.balance + mockStETH.balanceOf(claimant);
        vm.prank(claimant); game.claimClaimable(claimantId);
        uint256 paid = claimant.balance + mockStETH.balanceOf(claimant) - paidBefore;
        assertEq(paid, 12 ether, "prior awards and prepaid subscriptions remain withdrawable");
        address[3] memory sinks = [ContractAddresses.VAULT, ContractAddresses.SDGNRS, ContractAddresses.GNRUS];
        uint256 beforeFunds;
        for (uint256 i; i < 3; ++i) beforeFunds += sinks[i].balance + mockStETH.balanceOf(sinks[i]);
        vm.warp(uint256(game.gameOverTimestamp()) + 30 days);
        game.mineRun(0);
        uint256 afterFunds;
        for (uint256 i; i < 3; ++i) afterFunds += sinks[i].balance + mockStETH.balanceOf(sinks[i]);
        assertEq(address(game).balance + mockStETH.balanceOf(address(game)), 0);
        assertEq(afterFunds - beforeFunds + paid, initial, "all funds reach claimable protocol sinks");
        uint256 holdersBefore = stakedHolder.balance + wrappedHolder.balance + late.balance
            + mockStETH.balanceOf(stakedHolder) + mockStETH.balanceOf(wrappedHolder) + mockStETH.balanceOf(late);
        vm.prank(stakedHolder);
        (uint256 stakedEth, uint256 stakedSteth,) = sdgnrs.burn(shares);
        vm.prank(wrappedHolder);
        (uint256 wrappedEth, uint256 wrappedSteth,) = dgnrs.burn(shares);
        vm.prank(late);
        (uint256 lateEth, uint256 lateSteth,) = sdgnrs.burn(lateShares);
        assertGt(lateEth + lateSteth, 0, "late record shares retain withdrawable backing");
        assertEq(sdgnrs.balanceOf(late), 0);
        assertGt(stakedEth + stakedSteth, 0, "sDGNRS backing is withdrawable");
        assertGt(wrappedEth + wrappedSteth, 0, "DGNRS backing is withdrawable");
        assertEq(sdgnrs.balanceOf(stakedHolder), 0);
        assertEq(dgnrs.balanceOf(wrappedHolder), 0);
        uint256 holdersPaid = stakedHolder.balance + wrappedHolder.balance + late.balance
            + mockStETH.balanceOf(stakedHolder) + mockStETH.balanceOf(wrappedHolder) + mockStETH.balanceOf(late) - holdersBefore;
        assertEq(holdersPaid, stakedEth + stakedSteth + wrappedEth + wrappedSteth + lateEth + lateSteth);
        uint256 sinksRemaining;
        for (uint256 i; i < 3; ++i) sinksRemaining += sinks[i].balance + mockStETH.balanceOf(sinks[i]);
        assertEq(sinksRemaining - beforeFunds + paid + holdersPaid, initial, "token exits preserve exact total backing");
    }

    function test_RefusedNormalTerminalRequestFallsBackAndPaysAllBacking() public { _hardEnding(6); }

    function test_NormalEndingConservesFundsAndTokenBacking() public { _hardEnding(5); }

    function test_HardStallBeforeRequestConservesFunds() public { _hardEnding(0); }
    function test_HardStallWaitingForVrfConservesFunds() public { _hardEnding(1); }
    function test_HardStallDeliveredUnpublishedConservesFunds() public { _hardEnding(2); }
    function test_HardStallBlockedTicketsConservesFunds() public { _hardEnding(3); }
    function test_HardStallBlockedLaterConsumersConservesFunds() public { _hardEnding(4); }
}
