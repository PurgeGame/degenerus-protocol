// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameMinerModule} from "../../contracts/modules/DegenerusGameMinerModule.sol";
import {DegenerusGameAdvanceModule} from "../../contracts/modules/DegenerusGameAdvanceModule.sol";
import {DegenerusGameGameOverModule} from "../../contracts/modules/DegenerusGameGameOverModule.sol";
import {IDegenerusGameRngModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {IVRFCoordinator} from "../../contracts/interfaces/IVRFCoordinator.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";

contract MinerProgressHarness is DegenerusGameMinerModule {
    function seed(MinerAction action) external {
        uint24 today = _simulatedDayIndex();
        dailyIdx = today;
        _afkingResetDay = today;
        purchaseStartDay = today;
        level = 10;
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        rngRequestTime = uint48(block.timestamp);
        rngWordCurrent = 1234;
        _setRngSessionPublished(true);
        _setRngComplete(true);
        _recordDailyRng(today, 1234);
        if (action >= MinerAction.Publish && action <= MinerAction.CertifyRead) _setRngComplete(false);
        if (action == MinerAction.Terminal) gameOver = true;
        if (action == MinerAction.Wait || action == MinerAction.Publish) {
            _setRngComplete(false);
            _setRngRequestActive(true);
            _setRngSessionPublished(false);
            if (action == MinerAction.Wait) rngWordCurrent = RNG_WORD_WAITING;
        }
        if (action == MinerAction.Tickets) ticketsFullyProcessed = false;
        if (action >= MinerAction.DailyGap && action <= MinerAction.DailyPhase) {
            rngLockedFlag = true;
            rngRequestDay = today + (action == MinerAction.DailyGap ? 2 : 1);
            if (action == MinerAction.DailyPhase) _recordDailyRng(rngRequestDay, 5678);
        }
        if (action == MinerAction.Afking) _pendingBoxCount = 1;
        if (action == MinerAction.HumanBoxes) humanReadComplete = false;
        if (action == MinerAction.Degenerette) degeneretteQueue[_rngReadBuffer()].push(0);
        if (action == MinerAction.Decimator) decBattleQueue = 1;
        if (action == MinerAction.Craps) lootboxRngPacked |= uint256(1) << (LR_CRAPS_PENDING_SHIFT + _rngReadBuffer());
        if (action == MinerAction.PrepareSubscriptions || action == MinerAction.RequestDaily) {
            dailyIdx = today - 1;
            subsFullyProcessed = action == MinerAction.RequestDaily;
        }
        if (action == MinerAction.RequestMidday) _lrWrite(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK, 1);
    }

    function pendingMidday() external { _lrWrite(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK, 1); }
    function wireCoordinator() external { vrfCoordinator = IVRFCoordinator(ContractAddresses.VRF_COORDINATOR); }
    function setMiddayThreshold(uint64 milliEth) external { _lrWrite(LR_THRESHOLD_SHIFT, LR_THRESHOLD_MASK, milliEth); }
    function pendingCrapsWrite() external {
        lootboxRngPacked |= uint256(1) << (LR_CRAPS_PENDING_SHIFT + _rngWriteBuffer());
    }
    function uncertify() external { _setRngComplete(false); }
    function rngComplete() external view returns (bool) { return _rngComplete(); }
    function rngConsumerStage() external view returns (uint8) { return _rngConsumerStage(); }
    function rngLocked() external view returns (bool) { return rngLockedFlag; }
    /// @dev The Game's creditless `advanceDue()` view: any selected action but Idle or Wait.
    function advanceDue() external view returns (bool) {
        MinerAction action = _nextMinerAction(address(0));
        return action != MinerAction.Idle && action != MinerAction.Wait;
    }
    function extsload(bytes32 slot) external view returns (bytes32 value) {
        assembly ("memory-safe") { value := sload(slot) }
    }
    function setCrapsRngPending(uint48 index, bool pending) external {
        require(msg.sender == ContractAddresses.CRAPS);
        uint256 mask = uint256(1) << (LR_CRAPS_PENDING_SHIFT + index);
        if (pending) lootboxRngPacked |= mask;
        else lootboxRngPacked &= ~mask;
    }
    function seedTerminalWait(bool latched, bool dead) external {
        dailyIdx = _simulatedDayIndex() - 31;
        _setRngComplete(false);
        _setRngRequestActive(true);
        _setRngSessionPublished(false);
        rngWordCurrent = RNG_WORD_WAITING;
        rngRequestTime = uint48(block.timestamp - (dead ? 15 days : 1 days));
        if (latched) { _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, 2); _setRngTerminal(); }
    }
    function seedTerminalRequestRefusal() external {
        dailyIdx = _simulatedDayIndex() - 31;
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
        _keeperSlot = uint64(uint256(day) * _BONUS_SLOTS_PER_DAY + remainder);
        if (opened) _boostBudget[day] = 1;
        if (remainder == 0) {
            _dayTickets[_keeperSlot] = entrants;
            for (uint256 i = 1; i <= entrants; ++i) {
                _bets[(uint256(_keeperSlot) << 64) | i] = uint160(address(uint160(0xA000 + i)));
            }
        } else _battles[bytes32(uint256(_keeperSlot))] = entrants;
    }
    function head() external view returns (uint64) { return _keeperSlot; }
    function binding(uint64 slot) external view returns (uint48) { return _slotIndex[slot]; }
    function cursor(uint64 slot) external view returns (uint64) { return _bonusCursor[slot]; }
    function credits(address player) external view returns (uint256) { return _passCredits[player]; }
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
        vm.mockCall(ContractAddresses.CRAPS, abi.encodeWithSignature("minerMaintenancePending()"), abi.encode(false));
        vm.mockCall(ContractAddresses.CRAPS, abi.encodeWithSignature("minerMaintenanceDueAt()"), abi.encode(uint256(0)));
        vm.mockCall(ContractAddresses.COINFLIP, abi.encodeWithSignature("creditFlip(address,uint256)"), bytes(""));
    }

    function _seed(DegenerusGameStorage.MinerAction action) private {
        game.seed(action);
        if (action == DegenerusGameStorage.MinerAction.Redemption) {
            vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(true));
        }
        if (action == DegenerusGameStorage.MinerAction.Maintenance) {
            vm.mockCall(ContractAddresses.CRAPS, abi.encodeWithSignature("minerMaintenancePending()"), abi.encode(true));
        }
        if (action == DegenerusGameStorage.MinerAction.RequestMidday) _fundCoordinator(100 ether);
        assertEq(game.minerAction(), uint8(action), "fixture action");
    }

    function _fundCoordinator(uint96 link) private {
        game.wireCoordinator();
        vm.mockCall(ContractAddresses.VRF_COORDINATOR, abi.encodeWithSelector(IVRFCoordinator.getSubscription.selector),
            abi.encode(link, uint96(0), uint64(0), address(0), new address[](0)));
    }

    function _expectFailure(bytes4 reason, uint256 limit) private returns (uint256 used) {
        vm.recordLogs();
        uint256 before = gasleft();
        (bool ok, bytes memory data) = address(game).call{gas: limit}(abi.encodeCall(game.mineFlip, ()));
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
        assertLt(_expectFailure(DegenerusGameMinerModule.NoWork.selector, 16_700_000), 100_000);
        _expectFailure(DegenerusGameMinerModule.NoWork.selector, 150_000);
        game.seed(DegenerusGameStorage.MinerAction.Wait);
        assertFalse(game.advanceDue());
        assertLt(_expectFailure(DegenerusGameMinerModule.RngNotReady.selector, 16_700_000), 100_000);
        _expectFailure(DegenerusGameMinerModule.RngNotReady.selector, 150_000);
    }

    function test_ObservedMaintenanceDoneWithoutProgressStopsAfterOneDispatch() public {
        _seed(DegenerusGameStorage.MinerAction.Maintenance);
        assertTrue(game.advanceDue());
        assertEq(game.rngConsumerStage(), 7);
        bytes memory selector = abi.encodeWithSignature("runCrapsMaintenance(uint256)");
        vm.mockCall(ContractAddresses.CRAPS, selector, abi.encode(false, true, uint256(0)));
        vm.expectCall(ContractAddresses.CRAPS, selector, uint64(1));
        assertLt(_expectFailure(DegenerusGameMinerModule.NoWork.selector, 16_700_000), 200_000);
        assertEq(game.minerAction(), 16);
    }

    function _worker(DegenerusGameStorage.MinerAction action) private pure returns (address, bytes memory) {
        if (action == DegenerusGameStorage.MinerAction.Terminal) return (ContractAddresses.GAME_ADVANCE_MODULE, abi.encodeWithSignature("runTerminalPhase(uint256)"));
        if (action == DegenerusGameStorage.MinerAction.DailyPhase) return (ContractAddresses.GAME_ADVANCE_MODULE, abi.encodeWithSignature("runDailyPhase(uint256)"));
        if (action == DegenerusGameStorage.MinerAction.Redemption) return (ContractAddresses.SDGNRS, abi.encodeWithSignature("runRedemptionWork(uint256)"));
        if (action == DegenerusGameStorage.MinerAction.Afking) return (ContractAddresses.GAME_AFKING_MODULE, abi.encodeWithSignature("runAfkingWork(uint256)"));
        if (action == DegenerusGameStorage.MinerAction.HumanBoxes) return (ContractAddresses.GAME_AFKING_MODULE, abi.encodeWithSignature("runHumanBoxWork(uint256)"));
        if (action == DegenerusGameStorage.MinerAction.Degenerette) return (ContractAddresses.GAME_DEGENERETTE_MODULE, abi.encodeWithSignature("runDegeneretteWork(uint256)"));
        if (action == DegenerusGameStorage.MinerAction.Decimator) return (ContractAddresses.GAME_DECIMATOR_MODULE, abi.encodeWithSignature("runDecimatorWork(uint256)"));
        if (action == DegenerusGameStorage.MinerAction.Craps) return (ContractAddresses.CRAPS, abi.encodeWithSignature("runCrapsReadWork(uint48,uint256)"));
        if (action == DegenerusGameStorage.MinerAction.PrepareSubscriptions) return (ContractAddresses.GAME_AFKING_MODULE, abi.encodeWithSignature("runSubscriberWork(uint24,uint256)"));
        return (ContractAddresses.CRAPS, abi.encodeWithSignature("runCrapsMaintenance(uint256)"));
    }

    function test_EveryResultWorkerStopsOnUnchangedDoneOrGasCheckpoint() public {
        uint8[10] memory actions = [uint8(1), 7, 8, 9, 10, 11, 12, 13, 15, 16];
        for (uint256 i; i < actions.length; ++i) {
            uint256 snap = vm.snapshotState();
            DegenerusGameStorage.MinerAction action = DegenerusGameStorage.MinerAction(actions[i]);
            _seed(action);
            (address target, bytes memory selector) = _worker(action);
            vm.mockCall(target, selector, abi.encode(false, true, type(uint256).max));
            _expectFailure(DegenerusGameMinerModule.NoWork.selector, 16_700_000);
            vm.mockCall(target, selector, abi.encode(false, false, uint256(0)));
            _expectFailure(MineFlipGas.InsufficientExecutionGas.selector, 16_700_000);
            vm.revertToState(snap);
            // Mock state is not reverted with EVM snapshots.
            vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(false));
            vm.mockCall(ContractAddresses.CRAPS, abi.encodeWithSignature("minerMaintenancePending()"), abi.encode(false));
        }
    }

    function test_IndivisibleActionsRejectGasBeforeCallingTheirWorker() public {
        uint8[4] memory actions = [uint8(5), 6, 17, 18];
        for (uint256 i; i < actions.length; ++i) {
            uint256 snap = vm.snapshotState();
            _seed(DegenerusGameStorage.MinerAction(actions[i]));
            _expectFailure(MineFlipGas.InsufficientExecutionGas.selector, 500_000);
            vm.revertToState(snap);
        }
    }

    function test_OptionalRequestRefusalsBubbleWithoutWorkButKeepCertification() public {
        bytes4[5] memory reasons = [IDegenerusGameRngModule.GasTooHigh.selector,
            IDegenerusGameRngModule.PreResetWindow.selector, IDegenerusGameRngModule.InsufficientLink.selector,
            IDegenerusGameRngModule.NoPendingLootbox.selector, IDegenerusGameRngModule.BelowThreshold.selector];
        _seed(DegenerusGameStorage.MinerAction.RequestMidday);
        for (uint256 i; i < reasons.length; ++i) {
            vm.mockCallRevert(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSignature("requestMinerRng()"), abi.encodeWithSelector(reasons[i]));
            _expectFailure(reasons[i], 16_700_000);
            game.uncertify();
            vm.recordLogs();
            game.mineFlip{gas: 16_700_000}();
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
        bytes memory request = abi.encodeWithSignature("requestMinerRng()");
        game.setMiddayThreshold(500);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.Idle), "below threshold is idle");
        vm.expectCall(ContractAddresses.GAME_RNG_MODULE, request, 0);
        _expectFailure(DegenerusGameMinerModule.NoWork.selector, 16_700_000);
        game.setMiddayThreshold(0);
        _fundCoordinator(1 ether);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.Idle), "LINK floor is checked first");
        game.pendingCrapsWrite();
        _fundCoordinator(10 ether);
        game.setMiddayThreshold(500);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.RequestMidday),
            "pending Craps window waives the value gates at its own LINK floor");
    }

    function test_IneligibleOptionalRequestKeepsEarlierWorkWithoutAttempt() public {
        _seed(DegenerusGameStorage.MinerAction.RequestMidday);
        game.setMiddayThreshold(500);
        game.uncertify();
        vm.expectCall(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSignature("requestMinerRng()"), 0);
        vm.recordLogs();
        game.mineFlip{gas: 16_700_000}();
        assertTrue(game.rngComplete(), "earlier work commits without a request attempt");
        _assertWorkUnpaid();
    }

    function test_UsefulCertificationCommitsWhenNextWorkerDeclines() public {
        _seed(DegenerusGameStorage.MinerAction.Maintenance);
        bytes memory selector = abi.encodeWithSignature("runCrapsMaintenance(uint256)");
        for (uint256 mode; mode < 5; ++mode) {
            game.uncertify();
            if (mode < 2) vm.mockCall(ContractAddresses.CRAPS, selector, abi.encode(false, mode == 0, uint256(0)));
            else vm.mockCallRevert(ContractAddresses.CRAPS, selector, abi.encodeWithSelector(
                mode == 2 ? MineFlipGas.InsufficientExecutionGas.selector :
                mode == 3 ? DegenerusGameMinerModule.NoWork.selector : DegenerusGameMinerModule.RngNotReady.selector));
            vm.recordLogs();
            game.mineFlip{gas: 16_700_000}();
            assertTrue(game.rngComplete());
            _assertWorkUnpaid();
        }
    }

    function test_InvariantFailureStillRollsBackEarlierWork() public {
        _seed(DegenerusGameStorage.MinerAction.Maintenance);
        game.uncertify();
        vm.mockCallRevert(ContractAddresses.CRAPS, abi.encodeWithSignature("runCrapsMaintenance(uint256)"),
            abi.encodeWithSelector(MineFlipGas.WorkGasBound.selector));
        _expectFailure(MineFlipGas.WorkGasBound.selector, 16_700_000);
        assertFalse(game.rngComplete());
    }

    function test_ExhaustedWorkerGasRevertsWithoutWorkAndKeepsAUsefulPrefix() public {
        _seed(DegenerusGameStorage.MinerAction.Maintenance);
        bytes memory selector = abi.encodeWithSignature("runCrapsMaintenance(uint256)");
        vm.mockCallRevert(ContractAddresses.CRAPS, selector, bytes(""));
        _expectFailure(MineFlipGas.InsufficientExecutionGas.selector, 800_000);
        game.uncertify();
        vm.recordLogs();
        game.mineFlip{gas: 800_000}();
        assertTrue(game.rngComplete());
        _assertWorkUnpaid();
        vm.mockCallRevert(ContractAddresses.CRAPS, selector, abi.encodeWithSelector(DegenerusGameStorage.EmptyRevert.selector));
        _expectFailure(MineFlipGas.InsufficientExecutionGas.selector, 800_000);
        game.uncertify();
        vm.recordLogs();
        game.mineFlip{gas: 800_000}();
        assertTrue(game.rngComplete());
        _assertWorkUnpaid();
    }

    function _realTable() private returns (MinerMaintenanceTable table) {
        vm.clearMockedCalls();
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(false));
        vm.mockCall(ContractAddresses.COINFLIP, abi.encodeWithSignature("creditFlip(address,uint256)"), bytes(""));
        vm.etch(ContractAddresses.CRAPS, address(new MinerMaintenanceTable()).code);
        vm.etch(ContractAddresses.JACKPOT_BATTLE, address(new JackpotBattle()).code);
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
            assertFalse(table.minerMaintenancePending());
            _expectFailure(DegenerusGameMinerModule.NoWork.selector, 16_700_000);
            // Direct idle maintenance reports no progress, even without an eligible clock step.
            vm.prank(address(game));
            MineFlipGas.Result memory idle = table.runCrapsMaintenance(3_000_000);
            assertFalse(idle.progressed);
            assertTrue(idle.done);
            vm.warp(start + closes[p]);
            assertTrue(table.minerMaintenancePending());
            vm.recordLogs();
            game.mineFlip{gas: 16_700_000}();
            assertEq(table.binding(uint64(uint256(DAY) * 8 + p + 1)), 1);
            assertFalse(table.minerMaintenancePending(), "armed unresolved battle awaits RNG");
            _assertWorkUnpaid();
            vm.revertToState(snap);
        }
    }

    function test_DailyJackpotIsExcludedAndDayRolloverAdvancesOnce() public {
        MinerMaintenanceTable table = _realTable();
        game.seed(DegenerusGameStorage.MinerAction.Idle);
        table.seedHead(DAY, 6, 1, true);
        vm.warp(start + 1 days - 1);
        assertFalse(table.minerMaintenancePending());
        _expectFailure(DegenerusGameMinerModule.NoWork.selector, 16_700_000);
        vm.prank(address(game));
        assertFalse(table.runCrapsMaintenance(3_000_000).progressed);
        table.seedHead(DAY + 1, 0, 0, false);
        vm.warp(start + 2 days);
        game.seed(DegenerusGameStorage.MinerAction.Idle);
        vm.recordLogs();
        game.mineFlip{gas: 16_700_000}();
        assertEq(table.head(), uint64(uint256(DAY + 2) * 8));
        _assertWorkUnpaid();
        _expectFailure(DegenerusGameMinerModule.NoWork.selector, 16_700_000);
    }

    function test_MaintenanceCannotBypassAnOutstandingRngRequest() public {
        MinerMaintenanceTable table = _realTable();
        game.seed(DegenerusGameStorage.MinerAction.Wait);
        table.seedHead(DAY, 1, 1, true);
        assertTrue(table.minerMaintenancePending());
        _expectFailure(DegenerusGameMinerModule.RngNotReady.selector, 16_700_000);
        assertEq(table.binding(uint64(uint256(DAY) * 8 + 1)), 0);
    }

    function test_LapsedRefundsMatchAcrossGasLimitsIncluding167M() public {
        MinerMaintenanceTable table = _realTable();
        game.seed(DegenerusGameStorage.MinerAction.Idle);
        uint64 head = uint64(uint256(DAY - 1) * 8);
        table.seedHead(DAY - 1, 0, 80, false);
        _expectFailure(MineFlipGas.InsufficientExecutionGas.selector, 250_000);
        _expectFailure(MineFlipGas.InsufficientExecutionGas.selector, 500_000);
        assertEq(table.cursor(head), 0);
        uint256[4] memory limits = [uint256(800_000), 2_000_000, 9_500_000, 16_700_000];
        for (uint256 j; j < limits.length; ++j) {
            uint256 snap = vm.snapshotState();
            uint256 calls;
            while (table.head() == head && calls++ < 100) {
                uint256 before = table.cursor(head);
                vm.cool(address(table));
                vm.cool(ContractAddresses.JACKPOT_BATTLE);
                vm.recordLogs();
                game.mineFlip{gas: limits[j]}();
                assertGt(table.cursor(head), before, "every success refunds actual seats");
                if (j == 0) _assertWorkUnpaid();
            }
            assertLt(calls, 100);
            if (j == 0) assertGt(calls, 1, "small gas commits a useful partial prefix");
            assertEq(table.cursor(head), 80);
            assertEq(table.head(), head + 8);
            for (uint256 i = 1; i <= 80; ++i) assertEq(table.credits(address(uint160(0xA000 + i))), 1);
            _expectFailure(DegenerusGameMinerModule.NoWork.selector, 16_700_000);
            vm.revertToState(snap);
        }
    }

    function _terminalWorkers() private {
        vm.etch(ContractAddresses.GAME_ADVANCE_MODULE, address(new DegenerusGameAdvanceModule()).code);
        vm.etch(ContractAddresses.GAME_GAMEOVER_MODULE, address(new DegenerusGameGameOverModule()).code);
        vm.mockCall(ContractAddresses.AFFILIATE, abi.encodeWithSignature("affiliateTop(uint24)"), abi.encode(address(0), uint256(0)));
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
        game.mineFlip{gas: 16_700_000}();
        _assertWorkUnpaid();
        assertEq(game.minerAction(), 2);
        assertLt(_expectFailure(DegenerusGameMinerModule.RngNotReady.selector, 16_700_000), 100_000);
        vm.warp(block.timestamp + 15 days);
        assertEq(game.minerAction(), 1, "dead VRF fallback must remain reachable");
    }

    function test_TerminalRefusalTimerIsRealOnlyOnItsFirstWrite() public {
        _terminalWorkers();
        vm.etch(ContractAddresses.VRF_COORDINATOR, address(new MinerRefusingCoordinator()).code);
        _seed(DegenerusGameStorage.MinerAction.Idle);
        game.seedTerminalRequestRefusal();
        vm.recordLogs();
        game.mineFlip{gas: 16_700_000}();
        _assertWorkUnpaid();
        _expectFailure(MinerRefusingCoordinator.TransportRefused.selector, 16_700_000);
    }
}
