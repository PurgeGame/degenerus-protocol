// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IStETH} from "../../contracts/interfaces/IStETH.sol";
import {IVRFCoordinator} from "../../contracts/interfaces/IVRFCoordinator.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {IDegenerusGameAdvanceModule, IDegenerusGameJackpotModule, IDegenerusGameGameOverModule, IDegenerusGameRngModule}
    from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {NativeFailureExport, NativeFailureProbe} from "../helpers/NativeFailureExport.sol";
import {Vm} from "forge-std/Vm.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @dev Preserve dependency storage and normal behavior except the selected selector.
contract SelectorFaultProxy {
    address immutable implementation;
    bytes4 immutable selected;
    uint8 immutable mode;
    constructor(address target, bytes4 selector, uint8 fault) {
        implementation = target; selected = selector; mode = fault;
    }
    fallback() external payable {
        bool fault = msg.sig == selected;
        if (fault) {
            uint8 m = mode;
            if (m == 1) assembly ("memory-safe") { revert(0, 0) }
            if (m == 2) assembly ("memory-safe") { invalid() }
            if (m == 3) assembly ("memory-safe") { mstore(0, 1) return(31, 1) }
            if (m == 5) revert MineFlipGas.InsufficientExecutionGas();
            if (m == 6) assembly ("memory-safe") { mstore(0, not(0)) return(0, 32) }
            if (m == 7) assembly ("memory-safe") { mstore(0, 0) return(0, 32) }
            if (m == 9) revert("plain refusal");
            if (m == 10) assembly ("memory-safe") { for {} 1 {} {} }
            if (m == 8) {
                // A healthy coordinator upgrade can cost well above the former 500k cap.
                uint256 start = gasleft();
                while (start - gasleft() < 1_200_000) {}
            }
        }
        (bool ok, bytes memory result) = implementation.delegatecall(msg.data);
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        if (fault && mode == 12) {
            // Valid result with almost all forwarded gas spent: the next nested
            // dependency minimum must refuse atomically, never expire an account.
            while (gasleft() > 1_000) {}
        }
        if (fault && mode == 4) {
            // Valid prefix followed by 64 KiB; callers must never copy the tail.
            bytes memory large = new bytes(0x10000);
            assembly ("memory-safe") {
                for { let i := 0 } lt(i, mload(result)) { i := add(i, 32) } {
                    mstore(add(add(large, 32), i), mload(add(add(result, 32), i)))
                }
            }
            assembly ("memory-safe") { return(add(large, 32), mload(large)) }
        }
        assembly ("memory-safe") { return(add(result, 32), mload(result)) }
    }
}

contract GameIsolationHost is DegenerusGame {
    function invoke(address target, bytes calldata input) external returns (bytes memory result) {
        bool ok;
        (ok, result) = target.delegatecall(input);
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
    }
    function seedPhase() external {
        uint24 day = _wallDay();
        level = 1; dailyIdx = day; purchaseStartDay = day - 1;
        dailyComplete = false; lastDailyRequestWallDay = day; lastDailyCompletedAt = uint48(block.timestamp);
        rngRequestDay = day; rngRequestTime = uint48(block.timestamp);
        rngLockedFlag = true; ticketsFullyProcessed = true;
        phaseTransitionActive = true; vaultFlipSettledDay = day;
        _setRngSessionPublished(true); _recordDailyRng(day, 777);
        degenesisClosed = 7;
    }
    function seedRng(bool daily, bool prefix) external {
        uint24 day = _wallDay();
        level = 1; dailyIdx = daily ? day - 1 : day; purchaseStartDay = day;
        dailyComplete = true; lastDailyRequestWallDay = daily ? day - 1 : day;
        lastDailyCompletedAt = uint48(block.timestamp);
        _afkingResetDay = day; subsFullyProcessed = true;
        ticketsFullyProcessed = true; humanReadComplete = true;
        rngRequestTime = uint48(block.timestamp); rngRequestDay = 0; rngWordCurrent = 777;
        _setRngRequestActive(false); _setRngSessionPublished(true); _setRngComplete(!prefix);
        _recordDailyRng(day, 777);
        _lrWrite(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK, 1);
        _lrWrite(LR_THRESHOLD_SHIFT, LR_THRESHOLD_MASK, 0);
    }
    function seedTerminal(bool drain) external {
        level = 10; dailyIdx = _wallDay() - 31;
        lastDailyCompletedAt = uint48(block.timestamp - (drain ? 14 days : 0));
        degenesisClosed = 7; _setRngComplete(false); _setRngTerminal();
        _setRngRequestActive(false); _setRngSessionPublished(false);
        rngRequestDay = 0; rngRequestTime = 0; rngWordCurrent = RNG_WORD_WAITING;
        _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, 1);
        _lrWrite(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK, 0);
        if (drain) { _lrWrite(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK, 1); deadTallyStage = 3; }
    }
    function seedSweep(uint256 reserve) external {
        gameOver = true; _goWrite(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK, 1);
        _goWrite(GO_TIME_SHIFT, GO_TIME_MASK, block.timestamp - 31 days);
        _setRedemptionReserve(reserve); claimablePool += uint128(reserve);
    }
    function requestIdentity() external view returns (uint24, uint48, bool) {
        return (rngRequestDay, rngRequestTime, _rngRequestActive());
    }
    function nativeBalance() external view returns (bool, uint256) { return _vrfNativeBalance(); }
    function observedSteth() external view returns (uint256) { return _boundedStethBalance(MineFlipGas.fromCall(4), 100_000); }
    function requestProbe() external returns (bool, uint256) { return _boundedVrfRequest(6, MineFlipGas.fromCall(4)); }
    function swept() external view returns (bool) { return _goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0; }
}

contract GameExternalIsolationTest is DeployProtocol, NativeFailureExport {
    GameIsolationHost private host;
    address private tokenImplementation;
    address private vrfImplementation;
    address private adminImplementation;
    address private nativeAdmissionProbe;

    function _nativeExtraStorage(string memory key, address account) internal override {
        if (account != address(game) || nativeAdmissionProbe == address(0)) return;
        // A gas-limited native continuation can finish at the miner reward lookup
        // that the unlimited Foundry export does not visit. Export its actual
        // prestate value, including zero, rather than assuming an omitted slot.
        bytes32 slot = keccak256(abi.encode(nativeAdmissionProbe, GameSlots.WALLET_IDS));
        vm.serializeBytes32(key, vm.toString(slot), vm.load(account, slot));
    }

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 100 days);
        vm.etch(address(game), vm.getDeployedCode("GameExternalIsolation.t.sol:GameIsolationHost"));
        host = GameIsolationHost(payable(address(game)));
        tokenImplementation = address(0xF001);
        vrfImplementation = address(0xF002);
        adminImplementation = address(0xF003);
        vm.etch(tokenImplementation, address(mockStETH).code);
        vm.etch(vrfImplementation, address(mockVRF).code);
        vm.etch(adminImplementation, ContractAddresses.ADMIN.code);
        vm.mockCall(ContractAddresses.CRAPS, abi.encodeWithSignature("minerMaintenancePending_g11976()"), abi.encode(false));
        mockVRF.fundSubscription(1, uint96(100 ether));
    }
    function _fault(address target, address implementation, bytes4 selector, uint8 mode) private {
        vm.etch(target, address(new SelectorFaultProxy(implementation, selector, mode)).code);
    }
    function _phase() private returns (MineFlipGas.Result memory) {
        return abi.decode(host.invoke{gas: 10_000_000}(ContractAddresses.GAME_ADVANCE_MODULE,
            abi.encodeCall(IDegenerusGameAdvanceModule.runDailyPhase_g2582, (uint256(10_000_000)))), (MineFlipGas.Result));
    }
    function _terminal() private {
        host.invoke{gas: 10_000_000}(ContractAddresses.GAME_GAMEOVER_MODULE,
            abi.encodeCall(IDegenerusGameGameOverModule.runGameOverAdvance,
                (game.currentDayView(), uint24(10), uint256(10_000_000))));
    }

    function test_BalanceReadAllFailuresSkipYieldAndDaySealContinues() public {
        for (uint8 mode = 1; mode <= 6; ++mode) {
            uint256 snap = vm.snapshotState();
            host.seedPhase();
            vm.deal(address(game), 0);
            mockStETH.mint(address(game), 30 ether);
            _fault(address(mockStETH), tokenImplementation, IStETH.balanceOf.selector, mode);
            uint256 pool = game.claimablePoolView();
            host.invoke(ContractAddresses.GAME_JACKPOT_MODULE,
                abi.encodeCall(IDegenerusGameJackpotModule.distributeYieldSurplus, (uint256(777))));
            if (mode == 4) assertGt(game.claimablePoolView(), pool, "valid oversized prefix is honored");
            else assertEq(game.claimablePoolView(), pool, "unreadable balance distributes no yield");
            vm.recordLogs();
            MineFlipGas.Result memory result = _phase();
            assertTrue(result.progressed && result.done);
            assertFalse(game.rngLocked());
            Vm.Log[] memory logs = vm.getRecordedLogs();
            bool seen;
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics[0] == keccak256("PrizePoolDailySnapshot(uint256,uint256,uint256,uint256,uint256,uint256,uint24)")) {
                    (,,,, uint256 observed,,) = abi.decode(logs[i].data, (uint256,uint256,uint256,uint256,uint256,uint256,uint24));
                    assertEq(observed, mode == 4 ? 30 ether : 0);
                    seen = true;
                }
            }
            assertTrue(seen, "day seal emits its snapshot");
            vm.revertToState(snap);
        }
    }

    function test_DrainFailureLatchesAndFinalSweepConservesUnobservedSteth() public {
        for (uint8 mode = 1; mode <= 6; ++mode) {
            if (mode == 4) continue; // Successful prefix belongs to the normal balance path.
            uint256 snap = vm.snapshotState();
            host.seedTerminal(true);
            vm.deal(address(game), 0);
            mockStETH.mint(address(game), 30 ether);
            _fault(address(mockStETH), tokenImplementation, IStETH.balanceOf.selector, mode);
            _terminal();
            assertTrue(game.gameOver());
            assertEq(game.claimablePoolView(), 0);
            vm.etch(address(mockStETH), tokenImplementation.code);
            uint256 beforeTotal = mockStETH.balanceOf(ContractAddresses.VAULT)
                + mockStETH.balanceOf(ContractAddresses.SDGNRS) + mockStETH.balanceOf(ContractAddresses.GNRUS);
            vm.warp(block.timestamp + 31 days);
            _terminal();
            assertTrue(host.swept());
            uint256 afterTotal = mockStETH.balanceOf(ContractAddresses.VAULT)
                + mockStETH.balanceOf(ContractAddresses.SDGNRS) + mockStETH.balanceOf(ContractAddresses.GNRUS);
            assertEq(afterTotal - beforeTotal, 30 ether);
            assertEq(mockStETH.balanceOf(address(game)), 0);
            vm.revertToState(snap);
        }
    }

    function test_StakeFailureKeepsEthAndStillSealsDay() public {
        for (uint8 mode = 1; mode <= 7; ++mode) {
            if (mode == 6) continue;
            uint256 snap = vm.snapshotState();
            host.seedPhase(); vm.deal(address(game), 30 ether);
            _fault(address(mockStETH), tokenImplementation, IStETH.submit.selector, mode);
            assertTrue(_phase().done);
            assertEq(address(game).balance, mode == 4 ? 0 : 30 ether);
            assertEq(mockStETH.balanceOf(address(game)), mode == 4 ? 30 ether : 0);
            vm.revertToState(snap);
        }
    }

    function test_RequestRefusalRetainsPrefixAndRollsBackOwnPreparation() public {
        vm.expectCall(address(mockVRF), abi.encodeWithSelector(IVRFCoordinator.requestRandomWords.selector), uint64(12));
        for (uint256 kind; kind < 2; ++kind) for (uint8 mode = 1; mode <= 7; ++mode) {
            if (mode == 6) continue;
            uint256 snap = vm.snapshotState();
            host.seedRng(kind == 1, true);
            _fault(address(mockVRF), vrfImplementation, IVRFCoordinator.requestRandomWords.selector, mode);
            game.mineFlip{gas: 16_000_000}(0);
            (uint24 day,, bool active) = host.requestIdentity();
            if (mode == 4) assertTrue(active);
            else { assertFalse(active); assertEq(day, 0); assertTrue(game.rngComplete()); }
            vm.revertToState(snap);
        }
    }

    function test_ExpensiveCoordinatorRequestSucceedsBeyondFormerCap() public {
        host.seedRng(true, true);
        _fault(address(mockVRF), vrfImplementation, IVRFCoordinator.requestRandomWords.selector, 8);
        game.mineFlip{gas: 16_000_000}(0);
        (uint24 day,, bool active) = host.requestIdentity();
        assertGt(day, 0); assertTrue(active);
    }

    function test_ExpensiveSubscriptionReadSkipsAtFixedBudget() public {
        _fault(address(mockVRF), vrfImplementation, IVRFCoordinator.getSubscription.selector, 8);
        (bool ok, uint256 balance) = host.nativeBalance{gas: 3_000_000}();
        assertFalse(ok); assertEq(balance, 0);
    }

    function test_SelectorFailuresPreserveCertificationAndRefuseEligibility() public {
        for (uint8 mode = 1; mode <= 6; ++mode) {
            uint256 snap = vm.snapshotState();
            host.seedRng(false, true);
            _fault(address(mockVRF), vrfImplementation, IVRFCoordinator.getSubscription.selector, mode);
            vm.expectCall(address(mockVRF), abi.encodeWithSelector(IVRFCoordinator.getSubscription.selector));
            game.mineFlip{gas: 16_000_000}(0);
            if (mode != 4) { assertTrue(game.rngComplete()); (, , bool active) = host.requestIdentity(); assertFalse(active); }
            vm.revertToState(snap);
        }
    }

    function test_WorkerSubscriptionFailureRollsBackRequestPreparation() public {
        for (uint8 mode = 1; mode <= 6; ++mode) {
            uint256 snap = vm.snapshotState();
            host.seedRng(false, false);
            _fault(address(mockVRF), vrfImplementation, IVRFCoordinator.getSubscription.selector, mode);
            if (mode != 4) vm.expectRevert(DegenerusGameStorage.ExternalRequestRefused.selector);
            host.invoke(ContractAddresses.GAME_RNG_MODULE,
                abi.encodeCall(IDegenerusGameRngModule.requestMinerRng_g4954, ()));
            (uint24 day,, bool active) = host.requestIdentity();
            if (mode == 4) assertTrue(active);
            else { assertFalse(active); assertEq(day, 0); }
            vm.revertToState(snap);
        }
    }

    function test_TerminalRefusalsCannotPreventFourteenDayEnding() public {
        // Each fault mode is asked twice: by the arming call and by the retry a day later.
        vm.expectCall(address(mockVRF), abi.encodeWithSelector(IVRFCoordinator.requestRandomWords.selector), uint64(10));
        for (uint8 mode = 1; mode <= 7; ++mode) {
            if (mode == 4 || mode == 6) continue;
            uint256 snap = vm.snapshotState();
            host.seedTerminal(false);
            _fault(address(mockVRF), vrfImplementation, IVRFCoordinator.requestRandomWords.selector, mode);
            game.mineFlip{gas: 10_000_000}(0);
            (uint24 day, uint48 origin, bool active) = host.requestIdentity();
            assertGt(day, 0); assertGt(origin, 0); assertFalse(active);
            vm.warp(block.timestamp + 1 days);
            game.mineFlip{gas: 10_000_000}(0);
            (uint24 retryDay, uint48 retryOrigin, bool retryActive) = host.requestIdentity();
            assertEq(retryDay, day); assertEq(retryOrigin, origin); assertFalse(retryActive);
            vm.warp(uint256(origin) + 14 days + 1);
            for (uint256 i; i < 10 && !game.gameOver(); ++i) game.mineFlip{gas: 12_000_000}(0);
            assertTrue(game.gameOver(), "the dead ending remains reachable");
            vm.revertToState(snap);
        }
    }

    function test_ShutdownFailureRollsBackSweepAndRemainsRetryable() public {
        uint8[5] memory modes = [uint8(1), 2, 5, 9, 10];
        for (uint256 i; i < modes.length; ++i) {
            uint256 snap = vm.snapshotState();
            host.seedSweep(9 ether); vm.deal(address(game), 9 ether);
            _fault(ContractAddresses.ADMIN, adminImplementation, bytes4(keccak256("shutdownVrf()")), modes[i]);
            uint256 beforeSD = ContractAddresses.SDGNRS.balance;
            uint256 sub = admin.subscriptionId();
            bytes memory sweep = abi.encodeCall(IDegenerusGameGameOverModule.runGameOverAdvance,
                (game.currentDayView(), uint24(10), uint256(10_000_000)));
            vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
            host.invoke{gas: 10_000_000}(ContractAddresses.GAME_GAMEOVER_MODULE, sweep);
            assertFalse(host.swept()); assertEq(game.redemptionReserve(), 9 ether);
            assertEq(address(game).balance, 9 ether);
            assertEq(ContractAddresses.SDGNRS.balance, beforeSD);
            assertEq(admin.subscriptionId(), sub);
            vm.etch(ContractAddresses.ADMIN, adminImplementation.code);
            _terminal();
            assertTrue(host.swept()); assertEq(game.redemptionReserve(), 0);
            assertEq(admin.subscriptionId(), 0);
            assertEq(address(game).balance, 0);
            assertGe(ContractAddresses.SDGNRS.balance - beforeSD, 9 ether - 3);
            vm.revertToState(snap);
        }
    }

    function test_FinalSweepGasBoundaryNeverStrandsLiveSubscription() public {
        host.seedSweep(9 ether); vm.deal(address(game), 9 ether);
        uint256 sub = admin.subscriptionId();
        uint256 beforeSD = ContractAddresses.SDGNRS.balance;
        uint256 firstSuccess;
        for (uint256 supplied = 50_000; supplied <= 2_800_000; supplied += 5_000) {
            uint256 snap = vm.snapshotState();
            (bool ok,) = address(game).call{gas: supplied}(abi.encodeCall(game.mineFlip, (uint32(0))));
            if (ok) {
                assertTrue(host.swept()); assertEq(admin.subscriptionId(), 0);
                if (firstSuccess == 0) firstSuccess = supplied;
            } else {
                assertFalse(host.swept()); assertEq(admin.subscriptionId(), sub);
                assertEq(game.redemptionReserve(), 9 ether);
                assertEq(address(game).balance, 9 ether);
                assertEq(ContractAddresses.SDGNRS.balance, beforeSD);
            }
            assertTrue(vm.revertToState(snap)); vm.deleteStateSnapshot(snap);
        }
        assertGt(firstSuccess, 50_000); assertLt(firstSuccess, 2_800_000);
        emit log_named_uint("final_sweep_first_success_5k_grid", firstSuccess);
    }

    function test_RequestGasSweepPreservesCertificationAtBaselineAndFloor() public {
        for (uint256 kind; kind < 2; ++kind) for (uint256 calibration; calibration < 2; ++calibration) {
            for (uint256 supplied = 450_000; supplied <= 3_000_000; supplied += 25_000) {
                uint256 snap = vm.snapshotState();
                host.seedRng(kind == 0, true);
                uint32 multiplier = calibration == 0 ? 10_000 : 2_500;
                (bool ok,) = address(game).call{gas: supplied}(abi.encodeCall(game.mineFlip, (multiplier)));
                assertTrue(ok, "certification prefix must survive a declined request or re-selection");
                (,, bool active) = host.requestIdentity();
                if (!active) {
                    assertTrue(game.rngComplete(), "refusal cannot lose the certified read");
                    game.mineFlip{gas: 6_000_000}(multiplier);
                    (,, active) = host.requestIdentity();
                }
                assertTrue(active, "a refused request succeeds on a funded retry");
                assertTrue(vm.revertToState(snap)); vm.deleteStateSnapshot(snap);
            }
        }
    }

    function test_UnderfundedReadAndStakeAdmissionRevertsWithoutFailurePolicy() public {
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        host.observedSteth{gas: 50_000}();
        (bool readable, uint256 nativeAmount) = host.nativeBalance{gas: 50_000}();
        assertTrue(readable); assertGt(nativeAmount, 0);
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        host.requestProbe{gas: 500_000}();
        // Fixed-budget optional reads no longer impose an admission revert.
        host.invoke{gas: 500_000}(ContractAddresses.GAME_JACKPOT_MODULE,
            abi.encodeCall(IDegenerusGameJackpotModule.distributeYieldSurplus, (uint256(777))));
        vm.deal(address(game), 1 ether);
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        host.invoke{gas: 230_000}(ContractAddresses.GAME_ADVANCE_MODULE,
            abi.encodeCall(IDegenerusGameAdvanceModule.stakeExcessEth, (uint256(1 ether))));
        assertEq(address(game).balance, 1 ether);
    }
    function test_UnderfundedFinalShutdownRollsBackSweptMarkerAndTransfers() public {
        host.seedSweep(9 ether); vm.deal(address(game), 9 ether);
        uint256 beforeSD = ContractAddresses.SDGNRS.balance;
        (bool ok,) = address(game).call{gas: 50_000}(abi.encodeCall(game.mineFlip, (uint32(0))));
        assertFalse(ok, "underfunded first unit must roll back");
        assertFalse(host.swept());
        assertEq(game.redemptionReserve(), 9 ether);
        assertEq(address(game).balance, 9 ether);
        assertEq(ContractAddresses.SDGNRS.balance, beforeSD);
    }

    function test_NativeChangedGameBoundaries() public {
        vm.clearMockedCalls();
        // Seed the real table cursor at an empty current day; the ordinary fixture
        // mocked this predicate, which would hide the intended VRF boundary on native replay.
        bytes32 tableSlot = bytes32(uint256(11)); // CrapsBattleStorage._minerSlot, checked by layout oracle.
        uint256 tableWord = uint256(vm.load(ContractAddresses.CRAPS, tableSlot));
        vm.store(ContractAddresses.CRAPS, tableSlot,
            bytes32((tableWord & ~uint256(type(uint64).max)) | (uint256(game.currentDayView()) * 8)));
        NativeFailureProbe probe = new NativeFailureProbe();
        uint8[6] memory modes = [uint8(1), 2, 5, 8, 9, 10];
        for (uint256 site; site < 9; ++site) for (uint256 i; i < modes.length; ++i) {
            if ((site == 3 || site == 4) && i != 0) continue;
            this.exportNativeGameCase(site, modes[i], probe);
        }
    }

    function exportNativeGameCase(uint256 site, uint8 mode, NativeFailureProbe probe) external {
            uint256 snap = vm.snapshotState();
            bytes memory input;
            uint256 supplied = 10_000_000;
            if (site == 0) {
                host.seedRng(true, true);
                _seedCrapsFixtureCursor(game.currentDayView());
                vm.expectCall(address(mockVRF), abi.encodeWithSelector(IVRFCoordinator.requestRandomWords.selector));
                _fault(address(mockVRF), vrfImplementation, IVRFCoordinator.requestRandomWords.selector, mode);
                input = abi.encodeCall(game.mineFlip, (uint32(0)));
            } else if (site == 1) {
                _fault(address(mockVRF), vrfImplementation, IVRFCoordinator.getSubscription.selector, mode);
                input = abi.encodeCall(host.nativeBalance, ());
            } else if (site == 2) {
                host.seedSweep(9 ether); vm.deal(address(game), 9 ether);
                _fault(ContractAddresses.ADMIN, adminImplementation, bytes4(keccak256("shutdownVrf()")), mode);
                input = abi.encodeCall(host.invoke, (ContractAddresses.GAME_GAMEOVER_MODULE,
                    abi.encodeCall(IDegenerusGameGameOverModule.runGameOverAdvance,
                        (game.currentDayView(), uint24(10), uint256(10_000_000)))));
            }
            if (site >= 5) {
                bool terminal = site == 8;
                if (terminal) host.seedTerminal(true); else host.seedPhase();
                vm.deal(address(game), site == 6 ? 30 ether : 0);
                if (site != 6) mockStETH.mint(address(game), 30 ether);
                _fault(address(mockStETH), tokenImplementation,
                    site == 6 ? IStETH.submit.selector : IStETH.balanceOf.selector, mode);
                bytes memory worker = terminal
                    ? abi.encodeCall(IDegenerusGameGameOverModule.runGameOverAdvance,
                        (game.currentDayView(), uint24(10), uint256(10_000_000)))
                    : site == 7 ? abi.encodeCall(IDegenerusGameJackpotModule.distributeYieldSurplus, (uint256(777)))
                    : abi.encodeCall(IDegenerusGameAdvanceModule.runDailyPhase_g2582, (uint256(10_000_000)));
                input = abi.encodeCall(host.invoke,
                    (terminal ? ContractAddresses.GAME_GAMEOVER_MODULE : ContractAddresses.GAME_ADVANCE_MODULE, worker));
            }
            if (site == 3) { input = abi.encodeCall(host.requestProbe, ()); supplied = 500_000; }
            if (site == 4) { input = abi.encodeCall(host.nativeBalance, ()); supplied = 50_000; }
            _nativeCheckedFixture(string.concat("game-", vm.toString(site), "-", vm.toString(mode)),
                address(this), address(probe), abi.encodeCall(probe.invoke, (address(game), input, supplied)));
            require(vm.revertToState(snap));
            vm.deleteStateSnapshot(snap);
    }

    function test_NativeOptfixAdmissionBoundaries() public {
        vm.clearMockedCalls();
        bytes32 tableSlot = bytes32(uint256(11));
        uint256 tableWord = uint256(vm.load(ContractAddresses.CRAPS, tableSlot));
        vm.store(ContractAddresses.CRAPS, tableSlot,
            bytes32((tableWord & ~uint256(type(uint64).max)) | (uint256(game.currentDayView()) * 8)));
        NativeFailureProbe probe = new NativeFailureProbe();
        for (uint256 kind; kind < 3; ++kind) this.exportNativeAdmissionCase(kind, probe);
    }

    function exportNativeAdmissionCase(uint256 kind, NativeFailureProbe probe) external {
        require(msg.sender == address(this));
        nativeAdmissionProbe = address(probe);
        uint256 snap = vm.snapshotState();
        if (kind == 0) {
            host.seedSweep(9 ether); vm.deal(address(game), 9 ether);
        } else {
            host.seedRng(kind == 1, true);
            _seedCrapsFixtureCursor(game.currentDayView());
        }
        bytes memory input = abi.encodeCall(game.mineFlip, (uint32(10_000)));
        string memory label = kind == 0 ? "optfix-sweep" : kind == 1 ? "optfix-daily" : "optfix-midday";
        _nativeCheckedFixture(label, address(this), address(probe),
            abi.encodeCall(probe.invoke, (address(game), input, 6_000_000)));
        (bool ok,) = probe.invoke(address(game), input, 6_000_000);
        assertTrue(ok);
        if (kind == 0) {
            assertTrue(host.swept()); assertEq(admin.subscriptionId(), 0);
        } else {
            (,, bool active) = host.requestIdentity(); assertTrue(active);
        }
        assertTrue(vm.revertToState(snap)); vm.deleteStateSnapshot(snap);
    }

}
