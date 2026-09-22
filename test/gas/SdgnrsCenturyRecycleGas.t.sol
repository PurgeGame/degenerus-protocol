// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {BoundaryGasFixture, PhaseEndSeeder} from "./Lvl100PhaseEndAdvanceGas.t.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {Vm} from "forge-std/Vm.sol";

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
        _restore(realCode);
    }

    function _checkColdClose() internal {
        // setUp was a separate transaction. No production storage is read before measurement.
        vm.recordLogs();
        uint256 beforeGas = gasleft();
        game.advanceGame{gas: 16_777_216 - 21_064}();
        uint256 used = beforeGas - gasleft() + 21_064;
        emit log_named_uint("century refill + seed + 32 deity grants, cold gas including intrinsic", used);
        assertLt(used, 10_000_000, "comfort target");
        assertLt(used, 16_777_216, "hard transaction cap");
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
}

contract SdgnrsRecycleEmptyPoolsGasTest is SdgnrsRecycleGasFixture {
    function setUp() public { _setupRecycle(true); }
    function testColdCloseWithEmptyPoolsAndInventory() public { _checkColdClose(); }
}
