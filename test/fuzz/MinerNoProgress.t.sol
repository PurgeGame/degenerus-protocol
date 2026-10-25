// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {GameMiner} from "../../contracts/modules/GameMiner.sol";
import {MinerHarness} from "../helpers/MinerHarness.sol";
import {DegenerusGameAdvanceModule} from "../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {DegenerusGameDailyModule} from "../../contracts/modules/DegenerusGameDailyModule.sol";
import {DegenerusGameGameOverModule} from "../../contracts/modules/DegenerusGameGameOverModule.sol";
import {IDegenerusGameRngModule, IDegenerusGameMinerModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {IVRFCoordinator} from "../../contracts/interfaces/IVRFCoordinator.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsPreferenceLib} from "../../contracts/libraries/CrapsPreferenceLib.sol";

contract MinerProgressHarness is MinerHarness {
    function seed(MinerAction action) external {
        uint24 today = _wallDay();
        dailyIdx = today;
        dailyComplete = true;
        lastDailyCompletedAt = uint48(block.timestamp);
        lastDailyRequestWallDay = today;
        _afkingResetDay = today;
        purchaseStartDay = today;
        level = 10;
        degenesisClosed = 7;
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        rngRequestTime = uint48(block.timestamp);
        rngWordCurrent = 1234;
        _setRngSessionPublished(true);
        _setRngComplete(true);
        if (action != MinerAction.DailyApply) _recordDailyRng(today, 1234);
        if (action >= MinerAction.Publish && action <= MinerAction.CertifyRead) _setRngComplete(false);
        if (action == MinerAction.Terminal) gameOver = true;
        if (action == MinerAction.Wait || action == MinerAction.Publish) {
            _setRngComplete(false);
            _setRngRequest(vrfRequestId == 0 ? 1 : vrfRequestId);
            _setRngSessionPublished(false);
            if (action == MinerAction.Wait) rngWordCurrent = RNG_WORD_WAITING;
        }
        if (action == MinerAction.Tickets) ticketsFullyProcessed = false;
        if (action >= MinerAction.DailyApply && action <= MinerAction.DailyPhase) {
            rngLockedFlag = true;
            rngRequestDay = today;
            dailyComplete = false;
            if (action == MinerAction.DailyPhase) _recordDailyRng(rngRequestDay, 5678);
        }
        if (action == MinerAction.Afking) _pendingBoxCount = 1;
        if (action == MinerAction.HumanBoxes) humanReadComplete = false;
        if (action == MinerAction.Degenerette) degeneretteReadCount = 1;
        if (action == MinerAction.Decimator) decBattleQueue = 1;
        if (action == MinerAction.Craps) lootboxRngPacked |= uint256(1) << (LR_CRAPS_PENDING_SHIFT + _rngReadBuffer());
        if (action == MinerAction.PrepareSubscriptions || action == MinerAction.RequestDaily) {
            dailyIdx = today - 1;
            lastDailyRequestWallDay = today - 1;
            subsFullyProcessed = action == MinerAction.RequestDaily;
        }
        if (action == MinerAction.RequestMidday) _lrWrite(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK, 1);
        if (action == MinerAction.GrowthSettle) _setGrowthSettlePending(true);
        if (action == MinerAction.SeizeLoans) _setLoansDuePending(true);
    }

    function setGrowthPending(bool pending) external { _setGrowthSettlePending(pending); }
    function setLoansDue(bool pending) external { _setLoansDuePending(pending); }
    function growthPending() external view returns (bool) { return _growthSettlePending(); }

    function pendingMidday() external { _lrWrite(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK, 1); }
    function wireCoordinator() external { vrfCoordinator = IVRFCoordinator(ContractAddresses.VRF_COORDINATOR); }
    function setMiddayThreshold(uint64 milliEth) external { _lrWrite(LR_THRESHOLD_SHIFT, LR_THRESHOLD_MASK, milliEth); }
    function pendingCrapsWrite() external {
        lootboxRngPacked |= uint256(1) << (LR_CRAPS_PENDING_SHIFT + _rngWriteBuffer());
    }
    function uncertify() external { _setRngComplete(false); }
    function rngComplete() external view returns (bool) { return _rngComplete(); }
    function rngConsumerStage_g379() external view returns (uint8) { return _rngConsumerStage(); }
    function rngLocked() external view returns (bool) { return rngLockedFlag; }
    /// @dev The Game's creditless `advanceDue()` view: any selected action but Idle or Wait.
    function advanceDue() external view returns (bool) {
        MinerAction action = _nextMinerAction(address(0));
        return action != MinerAction.Idle && action != MinerAction.Wait;
    }
    function extsload_g2807007(bytes32 slot) external view returns (bytes32 value) {
        assembly ("memory-safe") { value := sload(slot) }
    }
    function setCrapsRngPending_g1406(uint48 index, bool pending) external {
        require(msg.sender == ContractAddresses.CRAPS);
        uint256 mask = uint256(1) << (LR_CRAPS_PENDING_SHIFT + index);
        if (pending) lootboxRngPacked |= mask;
        else lootboxRngPacked &= ~mask;
    }
    function seedTerminalWait(bool latched, bool dead) external {
        dailyIdx = _wallDay() - 1;
        purchaseStartDay = dailyIdx - 30;
        dailyComplete = true;
        lastDailyRequestWallDay = _wallDay() - 1;
        lastDailyCompletedAt = uint48(block.timestamp - 1 days);
        _setRngComplete(false);
        _setRngRequest(vrfRequestId == 0 ? 1 : vrfRequestId);
        _setRngSessionPublished(false);
        rngWordCurrent = RNG_WORD_WAITING;
        rngRequestTime = uint48(block.timestamp - (dead ? 15 days : 1 days));
        if (latched) { _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, 2); _setRngTerminal(); }
    }
    function seedTerminalRequestRefusal() external {
        dailyIdx = _wallDay() - 1;
        purchaseStartDay = dailyIdx - 30;
        dailyComplete = true;
        lastDailyRequestWallDay = _wallDay() - 1;
        lastDailyCompletedAt = uint48(block.timestamp - 1 days);
        _setRngComplete(false);
        _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, 2);
        _lrWrite(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK, 1);
        _setRngTerminal();
        rngWordCurrent = RNG_WORD_WAITING;
        vrfCoordinator = IVRFCoordinator(ContractAddresses.VRF_COORDINATOR);
    }
}

contract MinerRefusingCoordinator {
    error TransportRefused();
    fallback() external { revert TransportRefused(); }
}

contract MinerMaintenanceTable is CrapsBattle {
    function seedHead(uint24 day, uint8 remainder, uint32 entrants, bool opened) external {
        _minerSlot = uint64(uint256(day) * _BONUS_SLOTS_PER_DAY + remainder);
        if (opened) _storeBudget(day, 1);
        if (remainder == 0) {
            _storeDayTickets(_minerSlot, entrants);
            for (uint256 i = 1; i <= entrants; ++i) {
                _appendBet((uint256(_minerSlot) << 64) | i, 0xA000 + i);
            }
        } else _storeBattle(bytes32(uint256(_minerSlot)), entrants);
    }
    function head() external view returns (uint64) { return _minerSlot; }
    function binding(uint64 slot) external view returns (uint48) { return _slotIndexOf(slot); }
    function cursor(uint64 slot) external view returns (uint64) { return _bonusCursorOf(slot); }
    function credits(uint32 id) external view returns (uint256) { return _passCreditsById[id]; }
}

contract MinerNoProgressTest is Test {
    MinerProgressHarness private game;
    bytes32 private constant WORK = keccak256("MinerWork(address,uint8,uint256,uint256)");
    bytes32 private constant BOUNTY = keccak256("MinerBounty(uint8,address,uint256)");
    uint24 private constant DAY = 40;
    uint256 private start;

    function setUp() public {
        start = (uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) + DAY - 1) * 1 days + 82_620;
        vm.warp(start + 1 hours);
        vm.fee(1 gwei);
        vm.etch(ContractAddresses.GAME, address(new MinerProgressHarness()).code);
        game = MinerProgressHarness(ContractAddresses.GAME);
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(false));
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionBatchState()"),
            abi.encode(uint32(1), uint32(0), uint32(0), uint256(0)));
        vm.mockCall(ContractAddresses.CRAPS, abi.encodeWithSignature("minerMaintenancePending_g11976()"), abi.encode(false));
        vm.mockCall(ContractAddresses.COINFLIP, abi.encodeWithSignature("creditFlip_g317(uint32,uint256)"), bytes(""));
    }

    function _seed(DegenerusGameStorage.MinerAction action) private {
        game.seed(action);
        if (action == DegenerusGameStorage.MinerAction.Redemption) {
            vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(true));
        }
        if (action == DegenerusGameStorage.MinerAction.Maintenance) {
            vm.mockCall(ContractAddresses.CRAPS, abi.encodeWithSignature("minerMaintenancePending_g11976()"), abi.encode(true));
        }
        if (action == DegenerusGameStorage.MinerAction.RequestMidday) _fundCoordinator(100 ether);
        assertEq(game.minerAction(), uint8(action), "fixture action");
    }

    function _fundCoordinator(uint96 nativeBalance) private {
        game.wireCoordinator();
        vm.mockCall(ContractAddresses.VRF_COORDINATOR, abi.encodeWithSelector(IVRFCoordinator.getSubscription.selector),
            abi.encode(uint96(0), nativeBalance, uint64(0), address(0), new address[](0)));
    }

    function _expectFailure(bytes4 reason, uint256 limit) private returns (uint256 used) {
        vm.recordLogs();
        uint256 before = gasleft();
        (bool ok, bytes memory data) = address(game).call{gas: limit}(abi.encodeCall(game.mineFlip, (uint32(0))));
        used = before - gasleft();
        assertFalse(ok, "zero-work call must fail");
        assertEq(data, abi.encodeWithSelector(reason), "exact failure reason");
        assertEq(vm.getRecordedLogs().length, 0, "no work or bounty from zero work");
    }

    function _assertWorkUnpaid() private {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != BOUNTY, "no bounty below reward floor");
            if (logs[i].topics[0] == WORK) {
                ++count;
                (, uint256 used, uint256 reward) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                assertLt(used, MineFlipGas.MIN_REWARDED_GAS);
                assertEq(reward, 0);
            }
        }
        assertEq(count, 1);
    }

    function test_IdleAndWaitRevertBeforeDispatchAtLowAndHighGas() public {
        _seed(DegenerusGameStorage.MinerAction.Idle);
        assertLt(_expectFailure(GameMiner.NoWork.selector, 16_700_000), 100_000);
        _expectFailure(GameMiner.NoWork.selector, 150_000);
        game.seed(DegenerusGameStorage.MinerAction.Wait);
        assertFalse(game.advanceDue());
        assertLt(_expectFailure(IDegenerusGameMinerModule.RngNotReady.selector, 16_700_000), 100_000);
        _expectFailure(IDegenerusGameMinerModule.RngNotReady.selector, 150_000);
    }

    function test_ObservedMaintenanceDoneWithoutProgressStopsAfterOneDispatch() public {
        _seed(DegenerusGameStorage.MinerAction.Maintenance);
        assertTrue(game.advanceDue());
        assertEq(game.rngConsumerStage_g379(), 7);
        bytes memory selector = abi.encodeWithSignature("runCrapsMaintenance_g10712(uint256)");
        vm.mockCall(ContractAddresses.CRAPS, selector, abi.encode(false, true, uint256(0)));
        vm.expectCall(ContractAddresses.CRAPS, selector, uint64(1));
        assertLt(_expectFailure(GameMiner.NoWork.selector, 16_700_000), 200_000);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.Maintenance));
    }

    function _worker(DegenerusGameStorage.MinerAction action) private pure returns (address, bytes memory) {
        if (action == DegenerusGameStorage.MinerAction.Terminal) return (ContractAddresses.GAME_ADVANCE_MODULE, abi.encodeWithSignature("runTerminalPhase(uint256)"));
        if (action == DegenerusGameStorage.MinerAction.DailyPhase) return (ContractAddresses.GAME_ADVANCE_MODULE, abi.encodeWithSignature("runDailyPhase_g2582(uint256)"));
        if (action == DegenerusGameStorage.MinerAction.Redemption) return (ContractAddresses.SDGNRS, abi.encodeWithSignature("runRedemptionWork(uint256,uint256)"));
        if (action == DegenerusGameStorage.MinerAction.Afking) return (ContractAddresses.GAME_AFKING_MODULE, abi.encodeWithSignature("runAfkingWork_g8553(uint256)"));
        if (action == DegenerusGameStorage.MinerAction.HumanBoxes) return (ContractAddresses.GAME_AFKING_MODULE, abi.encodeWithSignature("runHumanBoxWork_g315(uint256)"));
        if (action == DegenerusGameStorage.MinerAction.Degenerette) return (ContractAddresses.GAME_DEGENERETTE_MODULE, abi.encodeWithSignature("runDegeneretteWork_g670(uint256)"));
        if (action == DegenerusGameStorage.MinerAction.Decimator) return (ContractAddresses.GAME_DECIMATOR_MODULE, abi.encodeWithSignature("runDecimatorWork(uint256)"));
        if (action == DegenerusGameStorage.MinerAction.Craps) return (ContractAddresses.CRAPS, abi.encodeWithSignature("runCrapsReadWork(uint48,uint256)"));
        if (action == DegenerusGameStorage.MinerAction.PrepareSubscriptions) return (ContractAddresses.GAME_AFKING_MODULE, abi.encodeWithSignature("runSubscriberWork_g6352(uint24,uint256)"));
        if (action == DegenerusGameStorage.MinerAction.SeizeLoans) return (ContractAddresses.GAME_ADVANCE_MODULE, abi.encodeWithSignature("runLoanSeizureWork(uint256)"));
        return (ContractAddresses.CRAPS, abi.encodeWithSignature("runCrapsMaintenance_g10712(uint256)"));
    }

    function test_EveryResultWorkerStopsOnUnchangedDoneOrGasCheckpoint() public {
        uint8[11] memory actions = [uint8(1), 6, 7, 8, 9, 10, 11, 12, 14, 15, 19];
        for (uint256 i; i < actions.length; ++i) {
            uint256 snap = vm.snapshotState();
            DegenerusGameStorage.MinerAction action = DegenerusGameStorage.MinerAction(actions[i]);
            _seed(action);
            (address target, bytes memory selector) = _worker(action);
            vm.mockCall(target, selector, abi.encode(false, true, type(uint256).max));
            _expectFailure(GameMiner.NoWork.selector, 16_700_000);
            vm.mockCall(target, selector, abi.encode(false, false, uint256(0)));
            _expectFailure(MineFlipGas.InsufficientExecutionGas.selector, 16_700_000);
            vm.revertToState(snap);
            // Mock state is not reverted with EVM snapshots.
            vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(false));
            vm.mockCall(ContractAddresses.CRAPS, abi.encodeWithSignature("minerMaintenancePending_g11976()"), abi.encode(false));
        }
    }

    function test_IndivisibleActionsAttemptFirstWorkerDespiteExtremeEstimate() public {
        uint8[3] memory actions = [uint8(5), 16, 17];
        for (uint256 i; i < actions.length; ++i) {
            uint256 snap = vm.snapshotState();
            _seed(DegenerusGameStorage.MinerAction(actions[i]));
            game.mineFlip{gas: 500_000}(type(uint32).max);
            vm.revertToState(snap);
        }
    }

    function test_MiddayPreflightAttemptsFirstUnitDespiteExtremeEstimate() public {
        _seed(DegenerusGameStorage.MinerAction.RequestMidday);
        vm.expectCall(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSelector(IDegenerusGameRngModule.requestMinerRng_g4954.selector));
        game.mineFlip{gas: 500_000}(type(uint32).max);
    }

    function test_SeizeLoansOutranksWaitAndEveryConsumerButNotTerminal() public {
        assertEq(uint8(DegenerusGameStorage.MinerAction.SeizeLoans), 19, "appended value");
        DegenerusGameStorage.MinerAction[5] memory behind = [DegenerusGameStorage.MinerAction.Wait,
            DegenerusGameStorage.MinerAction.Publish, DegenerusGameStorage.MinerAction.Tickets,
            DegenerusGameStorage.MinerAction.DailyPhase, DegenerusGameStorage.MinerAction.RequestDaily];
        for (uint256 i; i < behind.length; ++i) {
            uint256 snap = vm.snapshotState();
            _seed(behind[i]);
            game.setLoansDue(true);
            assertEq(game.minerAction(), 19, "seizure first");
            vm.revertToState(snap);
        }
        _seed(DegenerusGameStorage.MinerAction.Terminal);
        game.setLoansDue(true);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.Terminal), "the ending outranks seizure");
    }

    function test_GrowthSettleSelectedAfterRequestDailyAndBeforeRequestMidday() public {
        _seed(DegenerusGameStorage.MinerAction.GrowthSettle);
        assertEq(uint8(DegenerusGameStorage.MinerAction.GrowthSettle), 18, "appended value");
        assertEq(game.minerAction(), 18, "pending settlement is selected");
        game.pendingMidday();
        _fundCoordinator(100 ether);
        assertEq(game.minerAction(), 18, "settlement runs ahead of the mid-day request");
        game.seed(DegenerusGameStorage.MinerAction.RequestDaily);
        game.setGrowthPending(true);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.RequestDaily), "the daily request runs first");
        game.seed(DegenerusGameStorage.MinerAction.Maintenance);
        game.setGrowthPending(true);
        vm.mockCall(ContractAddresses.CRAPS, abi.encodeWithSignature("minerMaintenancePending_g11976()"), abi.encode(true));
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.Maintenance), "maintenance runs first");
    }

    function test_GrowthSettleClearsItsBitOnlyWhenDone() public {
        _seed(DegenerusGameStorage.MinerAction.GrowthSettle);
        bytes memory selector = abi.encodeWithSignature("runGrowthWork(uint256)");
        vm.mockCall(ContractAddresses.PARIMUTUEL, selector, abi.encode(true, false, uint256(1)));
        vm.expectCall(ContractAddresses.PARIMUTUEL, selector);
        game.mineFlip{gas: 16_700_000}(0);
        assertTrue(game.growthPending(), "unfinished settlement stays armed");
        assertEq(game.minerAction(), 18, "and is selected again");
        vm.mockCall(ContractAddresses.PARIMUTUEL, selector, abi.encode(true, true, uint256(1)));
        game.mineFlip{gas: 16_700_000}(0);
        assertFalse(game.growthPending(), "a finished settlement clears the bit");
    }

    function test_GrowthSettleAttemptsFirstUnitDespiteExtremeEstimate() public {
        _seed(DegenerusGameStorage.MinerAction.GrowthSettle);
        bytes memory selector = abi.encodeWithSignature("runGrowthWork(uint256)");
        vm.mockCall(ContractAddresses.PARIMUTUEL, selector, abi.encode(true, true, uint256(1)));
        vm.expectCall(ContractAddresses.PARIMUTUEL, selector);
        game.mineFlip{gas: 500_000}(type(uint32).max);
        assertFalse(game.growthPending(), "first funded checkpoint clears the bit");
    }

    function test_OptionalRequestRefusalsBubbleWithoutWorkButKeepCertification() public {
        bytes4[5] memory reasons = [IDegenerusGameRngModule.GasTooHigh.selector,
            IDegenerusGameRngModule.PreResetWindow.selector, IDegenerusGameRngModule.InsufficientNativeBalance.selector,
            IDegenerusGameRngModule.NoPendingLootbox.selector, IDegenerusGameRngModule.BelowThreshold.selector];
        _seed(DegenerusGameStorage.MinerAction.RequestMidday);
        for (uint256 i; i < reasons.length; ++i) {
            vm.mockCallRevert(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSignature("requestMinerRng_g4954()"), abi.encodeWithSelector(reasons[i]));
            _expectFailure(reasons[i], 16_700_000);
            game.uncertify();
            vm.recordLogs();
            game.mineFlip{gas: 16_700_000}(0);
            assertTrue(game.rngComplete(), "real certification survives a later refusal");
            _assertWorkUnpaid();
        }
    }

    /// @dev A mid-day request its own gates would refuse is not selected: no attempt is made,
    ///      earlier work commits, and with nothing else the call is NoWork. A pending
    ///      write-side Craps window keeps waiving the pending-value gates.
    function test_IneligibleOptionalRequestIsNeverAttempted() public {
        _seed(DegenerusGameStorage.MinerAction.RequestMidday);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.RequestMidday), "fixture: eligible");
        bytes memory request = abi.encodeWithSignature("requestMinerRng_g4954()");
        game.setMiddayThreshold(500);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.Idle), "below threshold is idle");
        vm.expectCall(ContractAddresses.GAME_RNG_MODULE, request, 0);
        _expectFailure(GameMiner.NoWork.selector, 16_700_000);
        game.setMiddayThreshold(0);
        // Below 1.5x the lane minimum (at least 0.0744 ETH for any callback limit) a lootbox
        // request is ineligible.
        _fundCoordinator(0.07 ether);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.Idle), "native floor is checked first");
        game.pendingCrapsWrite();
        _fundCoordinator(0);
        game.setMiddayThreshold(500);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.RequestMidday),
            "pending Craps window waives the value gates and the native floor");
    }

    function test_IneligibleOptionalRequestKeepsEarlierWorkWithoutAttempt() public {
        _seed(DegenerusGameStorage.MinerAction.RequestMidday);
        game.setMiddayThreshold(500);
        game.uncertify();
        vm.expectCall(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSignature("requestMinerRng_g4954()"), 0);
        vm.recordLogs();
        game.mineFlip{gas: 16_700_000}(0);
        assertTrue(game.rngComplete(), "earlier work commits without a request attempt");
        _assertWorkUnpaid();
    }

    function test_UsefulCertificationCommitsWhenNextWorkerDeclines() public {
        _seed(DegenerusGameStorage.MinerAction.Maintenance);
        bytes memory selector = abi.encodeWithSignature("runCrapsMaintenance_g10712(uint256)");
        for (uint256 mode; mode < 6; ++mode) {
            game.uncertify();
            if (mode < 2) vm.mockCall(ContractAddresses.CRAPS, selector, abi.encode(false, mode == 0, uint256(0)));
            else vm.mockCallRevert(ContractAddresses.CRAPS, selector, abi.encodeWithSelector(
                mode == 2 ? MineFlipGas.InsufficientExecutionGas.selector :
                mode == 3 ? GameMiner.NoWork.selector :
                mode == 4 ? IDegenerusGameMinerModule.RngNotReady.selector : MineFlipGas.WorkGasBound.selector));
            vm.recordLogs();
            game.mineFlip{gas: 16_700_000}(0);
            assertTrue(game.rngComplete());
            _assertWorkUnpaid();
        }
    }

    function test_InvariantFailureStillRollsBackEarlierWork() public {
        _seed(DegenerusGameStorage.MinerAction.Maintenance);
        game.uncertify();
        bytes4 invariant = bytes4(keccak256("InvariantBroken()"));
        vm.mockCallRevert(ContractAddresses.CRAPS, abi.encodeWithSignature("runCrapsMaintenance_g10712(uint256)"),
            abi.encodeWithSelector(invariant));
        _expectFailure(invariant, 16_700_000);
        assertFalse(game.rngComplete());
    }

    function test_WorkGasBoundWithoutPrefixStillReverts() public {
        _seed(DegenerusGameStorage.MinerAction.Maintenance);
        vm.mockCallRevert(ContractAddresses.CRAPS, abi.encodeWithSignature("runCrapsMaintenance_g10712(uint256)"),
            abi.encodeWithSelector(MineFlipGas.WorkGasBound.selector));
        _expectFailure(MineFlipGas.WorkGasBound.selector, 16_700_000);
    }

    function test_ExhaustedWorkerGasRevertsWithoutWorkAndKeepsAUsefulPrefix() public {
        _seed(DegenerusGameStorage.MinerAction.Maintenance);
        bytes memory selector = abi.encodeWithSignature("runCrapsMaintenance_g10712(uint256)");
        vm.mockCallRevert(ContractAddresses.CRAPS, selector, bytes(""));
        _expectFailure(MineFlipGas.InsufficientExecutionGas.selector, 800_000);
        game.uncertify();
        vm.recordLogs();
        game.mineFlip{gas: 800_000}(0);
        assertTrue(game.rngComplete());
        _assertWorkUnpaid();
        vm.mockCallRevert(ContractAddresses.CRAPS, selector, abi.encodeWithSelector(DegenerusGameStorage.EmptyRevert.selector));
        _expectFailure(MineFlipGas.InsufficientExecutionGas.selector, 800_000);
        game.uncertify();
        vm.recordLogs();
        game.mineFlip{gas: 800_000}(0);
        assertTrue(game.rngComplete());
        _assertWorkUnpaid();
    }

    function _realTable() private returns (MinerMaintenanceTable table) {
        vm.clearMockedCalls();
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(false));
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionBatchState()"),
            abi.encode(uint32(1), uint32(0), uint32(0), uint256(0)));
        vm.mockCall(ContractAddresses.COINFLIP, abi.encodeWithSignature("creditFlip_g317(uint32,uint256)"), bytes(""));
        vm.etch(ContractAddresses.CRAPS, address(new MinerMaintenanceTable()).code);

        return MinerMaintenanceTable(ContractAddresses.CRAPS);
    }

    function test_RealMaintenanceAtEveryWindowBoundaryAndIdleBeforeClose() public {
        MinerMaintenanceTable table = _realTable();
        uint256[5] memory closes = [uint256(20 minutes), 6 hours + 3 minutes,
            12 hours + 3 minutes, 18 hours + 3 minutes, 1 days - 20 minutes];
        for (uint8 p; p < 5; ++p) {
            uint256 snap = vm.snapshotState();
            game.seed(DegenerusGameStorage.MinerAction.Idle);
            table.seedHead(DAY, p + 1, 1, true);
            vm.warp(start + closes[p] - 1);
            assertFalse(table.minerMaintenancePending_g11976());
            _expectFailure(GameMiner.NoWork.selector, 16_700_000);
            // Direct idle maintenance reports no progress, even without an eligible clock step.
            vm.prank(address(game));
            MineFlipGas.Result memory idle = JackpotBattle(address(table)).runCrapsMaintenance_g10712(3_000_000);
            assertFalse(idle.progressed);
            assertTrue(idle.done);
            vm.warp(start + closes[p]);
            assertTrue(table.minerMaintenancePending_g11976());
            vm.recordLogs();
            game.mineFlip{gas: 16_700_000}(0);
            assertEq(table.binding(uint64(uint256(DAY) * 8 + p + 1)), 1);
            assertFalse(table.minerMaintenancePending_g11976(), "armed unresolved battle awaits RNG");
            _assertWorkUnpaid();
            vm.revertToState(snap);
        }
    }

    function test_DailyJackpotIsExcludedAndDayRolloverAdvancesOnce() public {
        MinerMaintenanceTable table = _realTable();
        game.seed(DegenerusGameStorage.MinerAction.Idle);
        table.seedHead(DAY, 6, 1, true);
        vm.warp(start + 1 days - 1);
        assertFalse(table.minerMaintenancePending_g11976());
        _expectFailure(GameMiner.NoWork.selector, 16_700_000);
        vm.prank(address(game));
        assertFalse(JackpotBattle(address(table)).runCrapsMaintenance_g10712(3_000_000).progressed);
        table.seedHead(DAY + 1, 0, 0, false);
        vm.warp(start + 2 days);
        game.seed(DegenerusGameStorage.MinerAction.Idle);
        vm.recordLogs();
        game.mineFlip{gas: 16_700_000}(0);
        assertEq(table.head(), uint64(uint256(DAY + 2) * 8));
        _assertWorkUnpaid();
        _expectFailure(GameMiner.NoWork.selector, 16_700_000);
    }

    function test_MaintenanceCannotBypassAnOutstandingRngRequest() public {
        MinerMaintenanceTable table = _realTable();
        game.seed(DegenerusGameStorage.MinerAction.Wait);
        table.seedHead(DAY, 1, 1, true);
        assertTrue(table.minerMaintenancePending_g11976());
        _expectFailure(IDegenerusGameMinerModule.RngNotReady.selector, 16_700_000);
        assertEq(table.binding(uint64(uint256(DAY) * 8 + 1)), 0);
    }

    function test_LapsedRefundsMatchAcrossGasLimitsIncluding167M() public {
        MinerMaintenanceTable table = _realTable();
        game.seed(DegenerusGameStorage.MinerAction.Idle);
        uint64 head = uint64(uint256(DAY - 1) * 8);
        table.seedHead(DAY - 1, 0, 80, false);
        assertEq(table.cursor(head), 0);
        uint256[6] memory limits = [uint256(250_000), 500_000, 800_000, 2_000_000, 9_500_000, 16_700_000];
        for (uint256 j; j < limits.length; ++j) {
            uint256 snap = vm.snapshotState();
            uint256 calls;
            while (table.head() == head && calls++ < 100) {
                uint256 before = table.cursor(head);
                vm.cool(address(table));
                vm.cool(ContractAddresses.JACKPOT_BATTLE);
                vm.recordLogs();
                game.mineFlip{gas: limits[j]}(0);
                assertTrue(table.cursor(head) > before || table.head() != head, "every success refunds seats or advances the completed head");
                if (j == 0) _assertWorkUnpaid();
            }
            assertLt(calls, 100);
            if (j == 0) assertGt(calls, 1, "small gas commits a useful partial prefix");
            assertEq(table.cursor(head), 80);
            assertEq(table.head(), head + 8);
            for (uint256 i = 1; i <= 80; ++i) assertEq(table.credits(uint32(0xA000 + i)), CrapsPreferenceLib.RETAINED | 1);
            _expectFailure(GameMiner.NoWork.selector, 16_700_000);
            vm.revertToState(snap);
        }
    }

    function _terminalWorkers() private {
        vm.etch(ContractAddresses.GAME_ADVANCE_MODULE, address(new DegenerusGameDailyModule()).code);
        vm.etch(ContractAddresses.GAME_GAMEOVER_MODULE, address(new DegenerusGameGameOverModule()).code);
        vm.mockCall(ContractAddresses.AFFILIATE, abi.encodeWithSignature("affiliateTop(uint24)"), abi.encode(uint32(0), uint96(0)));
    }

    function test_TerminalLowGasCannotMasqueradeAsWork() public {
        _terminalWorkers();
        _seed(DegenerusGameStorage.MinerAction.Terminal);
        _expectFailure(MineFlipGas.InsufficientExecutionGas.selector, 500_000);
    }

    function test_TerminalLatchCommitsOnceThenWaitingRevertsEarly() public {
        _terminalWorkers();
        _seed(DegenerusGameStorage.MinerAction.Idle);
        game.seedTerminalWait(false, false);
        assertEq(game.minerAction(), 1);
        vm.recordLogs();
        game.mineFlip{gas: 16_700_000}(0);
        _assertWorkUnpaid();
        assertEq(game.minerAction(), 1, "a VRF-alive decision settles the loan book before any wait");
        game.mineFlip{gas: 16_700_000}(0); // the (empty) loan book
        assertEq(game.minerAction(), 2);
        assertLt(_expectFailure(IDegenerusGameMinerModule.RngNotReady.selector, 16_700_000), 100_000);
        vm.warp(block.timestamp + 15 days);
        assertEq(game.minerAction(), 1, "dead VRF fallback must remain reachable");
    }

    function test_TerminalRefusalTimerIsRealOnlyOnItsFirstWrite() public {
        _terminalWorkers();
        vm.etch(ContractAddresses.VRF_COORDINATOR, address(new MinerRefusingCoordinator()).code);
        _seed(DegenerusGameStorage.MinerAction.Idle);
        game.seedTerminalRequestRefusal();
        vm.recordLogs();
        game.mineFlip{gas: 16_700_000}(0);
        _assertWorkUnpaid();
        vm.recordLogs();
        game.mineFlip{gas: 16_700_000}(0);
        assertEq(vm.getRecordedLogs().length, 0, "refusal with no progress earns no reward");
    }
}
