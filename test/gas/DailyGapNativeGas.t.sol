// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {NativeGasExport} from "../helpers/NativeGasExport.sol";
import {CoinflipStakeSetter} from "../helpers/CoinflipStakeSetter.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGasBounds as Bounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {Vm} from "forge-std/Vm.sol";

contract DailyGapNativeHost is DegenerusGame {
    function seedGap(uint256 word) external {
        uint24 today = _simulatedDayIndex();
        dailyIdx = today - 30;
        require(dailyIdx >= 1, "deploy day is one");
        // This fixture models a previously published frontier. Preserve its
        // ring/tag state; the separate lifecycle fixture constructs it naturally.
        _recordDailyRng(dailyIdx, 0xB007);
        purchaseStartDay = dailyIdx;
        lastPurchaseDay = true;
        lastVrfProcessedTimestamp = uint48(block.timestamp);
        rngRequestTime = uint48(block.timestamp);
        rngRequestDay = today;
        rngLockedFlag = true;
        rngWordCurrent = word;
        _setRngRequestActive(true);
        _setRngSessionPublished(true);
        ticketsFullyProcessed = true;
    }

    function applyGap() external {
        (bool ok, bytes memory reason) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(
            abi.encodeWithSignature("applyDailyGap()"));
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
    }

    function gapState() external view returns (uint24, uint24, bool) {
        return (dailyIdx, purchaseStartDay, rngGapApplied);
    }
}

contract DailyGapFlipSeeder is CoinflipStakeSetter {
    function seedGap(uint24 start, bool armed) external {
        flipsClaimableDay = start - 1;
        // The claimed frontier entails a published result for the previous day.
        // Without it a mid-page gap incorrectly charges a second fresh page.
        if (start > 1) {
            uint24 previous = start - 1;
            coinflipDayResultPacked[previous >> 5] = uint256(100) << ((previous & 31) * 8);
        }
        sdgnrsAutoRebuyArmed = armed;
        uint32 id = degenerusGame.walletIdOf_g3120(ContractAddresses.SDGNRS);
        PlayerCoinflipState storage s = playerState[id];
        s.lastClaim = start - 1;
        s.claimableStored = 1_000_000;
        s.autoRebuyCarry = armed ? 1_000 : 0;
        s.autoRebuyEnabled = armed;
        s.autoRebuyUnlimited = armed;
        s.autoRebuyStop = armed ? 1 : 0;
        s.autoRebuyStartDay = start - 1;
        _setFlipStake(start, id, 1_000);
    }
}

/// @dev Original calibration unit: the widest live 29-day gap, including
/// sDGNRS settlement and the transition through the seed window. Final code is
/// restored after fixture writers; only the Game's dispatch wrapper is a seam.
contract DailyGapNativeGasTest is DeployProtocol, NativeGasExport {
    function setUp() public { _deployProtocol(); }

    function _gapCase(uint24 wallDay, uint256 word, bool armed) private {
        vm.warp(82_620 + (uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) + wallDay - 1) * 1 days);
        uint24 today = game.currentDayView();
        assertGe(today, 31);
        vm.etch(address(game), type(DailyGapNativeHost).runtimeCode);
        DailyGapNativeHost host = DailyGapNativeHost(payable(address(game)));
        host.seedGap(word);
        bytes memory original = address(coinflip).code;
        vm.etch(address(coinflip), type(DailyGapFlipSeeder).runtimeCode);
        DailyGapFlipSeeder(address(coinflip)).seedGap(today - 29, armed);
        vm.etch(address(coinflip), original);
        uint256 snapshot = vm.snapshotState();
        vm.cool(address(game));
        vm.cool(address(coinflip));
        vm.recordLogs();
        host.applyGap();
        uint256 used = vm.lastCallGas().gasTotalUsed;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 resolved;
        bytes32 topic = keccak256("CoinflipDayResolved(uint24,bool,uint16,uint128)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(coinflip) && logs[i].topics.length != 0 && logs[i].topics[0] == topic) ++resolved;
        }
        assertEq(resolved, 29, "all 29 gap days settled");
        (uint24 idx, uint24 start, bool applied) = host.gapState();
        assertEq(idx, today - 1);
        assertEq(start, today - 1);
        assertTrue(applied);
        assertGt(game.rngWordForDay(today - 1), 0, "last gap word retained");
        assertEq(game.rngWordForDay(today), 0, "live day belongs to next checkpoint");
        assertLe(used, Bounds.DAILY_GAP, "cold widest-gap operation fits");
        emit log_named_uint("daily_gap29_cold_gas", used);
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            assertTrue(vm.revertToState(snapshot));
            this.exportNativeFixture(string.concat("daily-gap29-", vm.toString(wallDay), "-", vm.toString(word)),
                address(this), address(host), abi.encodeCall(host.applyGap, ()));
        }
        vm.deleteStateSnapshot(snapshot);
    }

    function test_NativeGap29SeedWindow() public { _gapCase(31, type(uint32).max, false); }
    function test_NativeGap29RebuyWins() public { _gapCase(60, type(uint32).max, true); }
    function test_NativeGap29RebuyLosses() public { _gapCase(60, 2, true); }
    function test_NativeGap29SeedFirstLoss() public { _gapCase(31, 4, false); }
    function test_NativeGap29SeedAfterWinLoss() public { _gapCase(31, 2, false); }
    function test_NativeGap29SeedAlternating() public { _gapCase(31, 0xaaaaaaaa, false); }
    function test_NativeGap29SeedLastLoss() public { _gapCase(31, (uint256(1) << 29) - 1, false); }
    function test_NativeGap29RebuyNewPage() public { _gapCase(61, 2, true); }
}

/// @dev Reach the widest gap from a day-one deployment and a real completed
/// day. No storage writer participates in this fixture's state construction.
contract DailyGapLifecycleGasTest is DeployProtocol, NativeGasExport {
    function _deployTimestamp() internal pure override returns (uint256) { return DEPLOY_TS_DEGENESIS; }
    function setUp() public { _deployProtocol(); }

    function _request() private {
        for (uint256 i; i < 512 && !game.rngLocked(); ++i) game.mineFlip(0);
        assertTrue(game.rngLocked(), "daily request through production");
    }

    function _minimalStep() private {
        uint256 lo = 50_000;
        uint256 hi = 16_000_000;
        while (hi - lo > 100) {
            uint256 snapshot = vm.snapshotState();
            uint256 mid = (lo + hi) / 2;
            (bool ok,) = address(game).call{gas: mid}(abi.encodeCall(game.mineFlip, (uint32(0))));
            assertTrue(vm.revertToStateAndDelete(snapshot));
            if (ok) hi = mid;
            else lo = mid;
        }
        game.mineFlip{gas: hi}(0);
    }

    function test_NativeGap29FromRealLifecycle() public {
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _request();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 4);
        _mineAll(512);
        assertFalse(game.advanceDue(), "initial day completed");
        assertTrue(game.rngComplete(), "initial consumers completed");
        vm.warp(vm.getBlockTimestamp() + 30 days);
        assertFalse(game.livenessTriggered(), "exactly 30 days remains live");
        _request();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 4);
        for (uint256 i; i < 512 && game.nextMinerAction() != 5; ++i) _minimalStep();
        assertEq(game.nextMinerAction(), 5, "production selects the 29-day gap");
        vm.etch(address(game), type(DailyGapNativeHost).runtimeCode);
        DailyGapNativeHost host = DailyGapNativeHost(payable(address(game)));
        uint256 snapshot = vm.snapshotState();
        vm.cool(address(host));
        vm.cool(address(coinflip));
        vm.recordLogs();
        host.applyGap();
        uint256 used = vm.lastCallGas().gasTotalUsed;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 resolved;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(coinflip) && logs[i].topics.length != 0
                && logs[i].topics[0] == keccak256("CoinflipDayResolved(uint24,bool,uint16,uint128)")) ++resolved;
        }
        assertEq(resolved, 29, "complete maximal live gap");
        assertLe(used, Bounds.DAILY_GAP);
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            assertTrue(vm.revertToState(snapshot));
            this.exportNativeFixture("daily-gap29-real-lifecycle", address(this), address(host), abi.encodeCall(host.applyGap, ()));
        }
        vm.deleteStateSnapshot(snapshot);
    }
}
