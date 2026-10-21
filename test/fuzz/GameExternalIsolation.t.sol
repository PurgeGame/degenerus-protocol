// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IStETH} from "../../contracts/interfaces/IStETH.sol";
import {IVRFCoordinator} from "../../contracts/interfaces/IVRFCoordinator.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {IDegenerusGameAdvanceModule, IDegenerusGameJackpotModule, IDegenerusGameGameOverModule, IDegenerusGameRngModule}
    from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {Vm} from "forge-std/Vm.sol";

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
        }
        (bool ok, bytes memory result) = implementation.delegatecall(msg.data);
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
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
        uint24 day = _simulatedDayIndex();
        level = 1; dailyIdx = day - 1; purchaseStartDay = day - 1;
        rngRequestDay = day; rngRequestTime = uint48(block.timestamp);
        rngLockedFlag = true; ticketsFullyProcessed = true;
        phaseTransitionActive = true; vaultFlipSettledDay = day;
        _setRngSessionPublished(true); _recordDailyRng(day, 777);
        degenesisClosed = 7;
    }
    function seedRng(bool daily, bool prefix) external {
        uint24 day = _simulatedDayIndex();
        level = 1; dailyIdx = daily ? day - 1 : day; purchaseStartDay = day;
        _afkingResetDay = day; subsFullyProcessed = true;
        ticketsFullyProcessed = true; humanReadComplete = true;
        rngRequestTime = uint48(block.timestamp); rngRequestDay = 0; rngWordCurrent = 777;
        _setRngRequestActive(false); _setRngSessionPublished(true); _setRngComplete(!prefix);
        _recordDailyRng(day, 777);
        _lrWrite(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK, 1);
        _lrWrite(LR_THRESHOLD_SHIFT, LR_THRESHOLD_MASK, 0);
    }
    function seedTerminal(bool drain) external {
        level = 10; dailyIdx = _simulatedDayIndex() - 31;
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
    function linkBalance() external view returns (bool, uint256) { return _vrfLinkBalance(); }
    function observedSteth() external view returns (uint256) { return _boundedStethBalance(); }
    function requestProbe() external returns (bool, uint256) { return _boundedVrfRequest(6); }
    function swept() external view returns (bool) { return _goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0; }
}

contract GameExternalIsolationTest is DeployProtocol {
    GameIsolationHost private host;
    address private tokenImplementation;
    address private vrfImplementation;
    address private adminImplementation;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 100 days);
        vm.etch(address(game), type(GameIsolationHost).runtimeCode);
        host = GameIsolationHost(payable(address(game)));
        tokenImplementation = address(0xF001);
        vrfImplementation = address(0xF002);
        adminImplementation = address(0xF003);
        vm.etch(tokenImplementation, address(mockStETH).code);
        vm.etch(vrfImplementation, address(mockVRF).code);
        vm.etch(adminImplementation, ContractAddresses.ADMIN.code);
        vm.mockCall(ContractAddresses.CRAPS, abi.encodeWithSignature("minerMaintenancePending()"), abi.encode(false));
        mockVRF.fundSubscription(1, uint96(100 ether));
    }
    function _fault(address target, address implementation, bytes4 selector, uint8 mode) private {
        vm.etch(target, address(new SelectorFaultProxy(implementation, selector, mode)).code);
    }
    function _phase() private returns (MineFlipGas.Result memory) {
        return abi.decode(host.invoke{gas: 10_000_000}(ContractAddresses.GAME_ADVANCE_MODULE,
            abi.encodeCall(IDegenerusGameAdvanceModule.runDailyPhase, (uint256(10_000_000)))), (MineFlipGas.Result));
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
                abi.encodeCall(IDegenerusGameRngModule.requestMinerRng, ()));
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

    function test_ShutdownFailureCannotUndoSweepOrSpendReserveOnOtherSinks() public {
        for (uint8 mode = 1; mode <= 5; ++mode) {
            uint256 snap = vm.snapshotState();
            host.seedSweep(9 ether); vm.deal(address(game), 9 ether);
            _fault(ContractAddresses.ADMIN, adminImplementation, bytes4(keccak256("shutdownVrf()")), mode);
            uint256 beforeSD = ContractAddresses.SDGNRS.balance;
            _terminal();
            assertTrue(host.swept()); assertEq(game.redemptionReserve(), 0);
            assertEq(address(game).balance, 0);
            assertGe(ContractAddresses.SDGNRS.balance - beforeSD, 9 ether - 3);
            vm.revertToState(snap);
        }
    }

    function test_UnderfundedReadAndStakeAdmissionRevertsWithoutFailurePolicy() public {
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        host.observedSteth{gas: 50_000}();
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        host.linkBalance{gas: 50_000}();
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        host.requestProbe{gas: 500_000}();
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        host.invoke{gas: 50_000}(ContractAddresses.GAME_JACKPOT_MODULE,
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
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        game.mineFlip{gas: 750_000}(0);
        assertFalse(host.swept());
        assertEq(game.redemptionReserve(), 9 ether);
        assertEq(address(game).balance, 9 ether);
        assertEq(ContractAddresses.SDGNRS.balance, beforeSD);
    }

}
