// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {BoundaryGasFixture, PhaseEndSeeder} from "./Lvl100PhaseEndAdvanceGas.t.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGameAdvanceModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {TicketQueueStorage as TQ} from "../fuzz/helpers/TicketQueueStorage.sol";

/// @dev The seeded transition day is the daily phase of a delivered, published request: the
///      engine selects DailyPhase only for an active, published, not-yet-complete session.
contract RecycleSessionSeeder is DegenerusGame {
    function openDailyPhase() external {
        rngRequestDay = _simulatedDayIndex();
        _setRngRequestActive(true);
        _setRngSessionPublished(true);
        _setRngComplete(false);
    }

    /// @dev Gross gas of one production daily-phase checkpoint (the century close) in isolation.
    function measuredDailyPhase(uint256 allowance) external returns (bool done, uint256 grossGas) {
        bytes memory data = abi.encodeWithSelector(IDegenerusGameAdvanceModule.runDailyPhase.selector, allowance);
        uint256 beforeGas = gasleft();
        (bool ok, bytes memory returned) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(data);
        grossGas = beforeGas - gasleft();
        if (!ok) assembly ("memory-safe") { revert(add(returned, 32), mload(returned)) }
        (, done,) = abi.decode(returned, (bool, bool, uint256));
    }
}

abstract contract SdgnrsRecycleGasFixture is BoundaryGasFixture {
    uint256 private constant RNG_WORD = uint256(keccak256("century-recycle-cold-close")) | 1;
    uint256 private constant REFILL_PERCENT = 25 + uint256(keccak256(abi.encode(
        RNG_WORD, uint256(keccak256("sdgnrs.century.refill")) ^ uint256(100)
    ))) % 51;
    uint256 internal expectedBurns;
    uint256 internal expectedSupply;

    function _setupRecycle(bool empty) internal {
        _deployProtocol();
        vm.startPrank(address(game));
        if (empty) {
            for (uint8 i; i < 4; ++i) {
                expectedBurns += sdgnrs.transferFromPool(sDGNRS.Pool(i), address(sdgnrs), type(uint256).max);
            }
            sdgnrs.transferFromPool(sDGNRS.Pool.PresaleBox, address(0xA11CE), type(uint256).max);
        } else {
            expectedBurns = sdgnrs.transferFromPool(sDGNRS.Pool.Whale, address(sdgnrs), 7_000 ether + 1);
        }
        vm.stopPrank();
        expectedSupply = sdgnrs.totalSupply() + expectedBurns * REFILL_PERCENT / 100;

        bytes memory realCode = address(game).code;
        PhaseEndSeeder seeder = _etchSeedRestore();
        seeder.seedTransitionDone(LVL, RNG_WORD);
        vm.etch(address(game), type(RecycleSessionSeeder).runtimeCode);
        RecycleSessionSeeder(payable(address(game))).openDailyPhase();
        _restore(realCode);
        // At the level-100 close every queue through level 100 has drained; the recycled far-future
        // roots (e.g. root 100 for the level-200 perpetual grants) are free to bind.
        TQ.retireCompleted(address(game), LVL);
    }

    /// @dev Per-chunk: the century close (transition close + refill + 20-day seed + 32 deity
    ///      grants) is one daily-phase checkpoint; cold, in isolation, it stays inside the 10M
    ///      realistic chunk limit. Its declared admission bound is logged beside the measurement.
    function _checkColdCloseChunk() internal {
        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(RecycleSessionSeeder).runtimeCode);
        (bool done, uint256 chunk) = RecycleSessionSeeder(payable(address(game))).measuredDailyPhase(10_000_000);
        vm.etch(address(game), realCode);
        emit log_named_uint("century close checkpoint, cold gross gas", chunk);
        emit log_named_uint("declared TRANSITION_CLOSE + DAILY_PHASE_TAIL", GasBounds.TRANSITION_CLOSE + GasBounds.DAILY_PHASE_TAIL);
        assertTrue(done, "the close completed in one checkpoint");
        assertEq(sdgnrs.lastRecycledCentury(), 1, "the refill ran inside the measured checkpoint");
        assertLe(chunk, 10_000_000, "century close checkpoint inside the realistic chunk limit");
    }

    function _checkColdClose() internal {
        // setUp was a separate transaction. No production storage is read before measurement.
        // A realistic 10M allowance must succeed and complete the close; the engine keeps admitting
        // chunks while the allowance covers the next declared bound, so the call is reported, not
        // bounded (the per-chunk bound is _checkColdCloseChunk).
        vm.recordLogs();
        uint256 beforeGas = gasleft();
        game.mineFlip{gas: 10_000_000}();
        uint256 used = beforeGas - gasleft() + 21_064;
        emit log_named_uint("century refill + seed + 32 deity grants, cold gas including intrinsic", used);
        bool recycled;
        bool seeded;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(sdgnrs) && logs[i].topics[0] == sDGNRS.CenturyRecycled.selector) {
                assertFalse(recycled, "one event per boundary");
                recycled = true;
                assertEq(uint256(logs[i].topics[1]), 100);
                (uint256 percent, uint256 burned, uint256 minted,,,,) = abi.decode(logs[i].data, (uint256,uint256,uint256,uint256,uint256,uint256,uint256));
                assertEq(percent, REFILL_PERCENT);
                assertEq(burned, expectedBurns);
                assertEq(minted, expectedBurns * REFILL_PERCENT / 100);
            }
            if (logs[i].topics[0] == SEED_ARMED_SIG) seeded = true;
        }
        assertTrue(recycled, "nonzero recycle executed in measured transaction");
        assertTrue(seeded, "20-day century seed executed in same transaction");
        assertEq(sdgnrs.totalSupply(), expectedSupply);
        assertEq(sdgnrs.centurySupplyCheckpoint(), expectedSupply);
        assertEq(sdgnrs.lastRecycledCentury(), 1);
        (, bool inJackpot,,,) = game.purchaseInfo();
        assertFalse(inJackpot, "next purchase phase opened");
        assertFalse(game.rngLocked());
        assertEq(wwxrp.totalSupply(), wwxrpBefore);

        vm.prank(address(game));
        sdgnrs.recycleCentury(100, RNG_WORD + 1);
        assertEq(sdgnrs.totalSupply(), expectedSupply, "repeat is inert");
    }
}

contract SdgnrsRecycleNonemptyPoolsGasTest is SdgnrsRecycleGasFixture {
    function setUp() public { _setupRecycle(false); }
    function testColdCloseWithNonemptyPools() public { _checkColdClose(); }
    function testColdCloseChunkWithNonemptyPools() public { _checkColdCloseChunk(); }
}

contract SdgnrsRecycleEmptyPoolsGasTest is SdgnrsRecycleGasFixture {
    function setUp() public { _setupRecycle(true); }
    function testColdCloseWithEmptyPoolsAndInventory() public { _checkColdClose(); }
    function testColdCloseChunkWithEmptyPoolsAndInventory() public { _checkColdCloseChunk(); }
}
