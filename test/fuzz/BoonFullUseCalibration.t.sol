// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {RngTags} from "../../contracts/libraries/RngTags.sol";
import {BoonBatchParityHarness, BoonBatchQuestRecorder} from "./BoonBatchParity.t.sol";

contract BoonCalibrationHarness is BoonBatchParityHarness {
    function expectedPerBoon(uint24 currentLevel) external pure returns (uint256) {
        return _boonAvgMaxValue(currentLevel);
    }
}

/// @notice One box boon's divisor is its full-use value, and a box at the 0.315-ETH budget cap
///         hits with chance 0.315 ETH / that value at every level.
contract BoonFullUseCalibrationTest is Test {
    uint256 private constant CAP = 0.315 ether;
    uint256 private constant PPM = 1_000_000;
    bytes32 private constant REWARD = keccak256("LootBoxReward(uint32,uint8,uint256,uint256)");
    bytes32 private constant WHALE_PASS =
        keccak256("LootBoxWhalePassJackpot(uint32,uint256,uint24,uint32,uint24,uint24)");
    bytes32 private constant DISCARDED = keccak256("BoonDiscarded(uint32,uint8)");

    BoonCalibrationHarness private boon;
    uint32 private boonId;

    function setUp() public {
        vm.warp(1_900_000_000);
        BoonCalibrationHarness implementation = new BoonCalibrationHarness();
        vm.etch(ContractAddresses.GAME, address(implementation).code);
        boon = BoonCalibrationHarness(ContractAddresses.GAME);
        boonId = boon.seed(address(0xB00B));
        vm.etch(ContractAddresses.QUESTS, address(new BoonBatchQuestRecorder()).code);
    }

    /// @dev Independent closed form: weight x full-use value over the 2,856-weight table. Fixed
    ///      families 820 ETH (2.4-ETH whale price through pass level 4: 8.8 ETH less); FLIP
    ///      families 8,742 tickets of the open level; lazy discounts 6 x the price charged.
    function _fullUse(uint24 currentLevel) private pure returns (uint256) {
        uint256 lazy;
        if (currentLevel <= 3) {
            lazy = 0.24 ether;
        } else {
            for (uint24 i; i < 10; ++i) lazy += PriceLookupLib.priceForLevel(currentLevel + i);
        }
        uint256 weighted = 820 ether + 8742 * PriceLookupLib.priceForLevel(currentLevel) + 6 * lazy;
        if (currentLevel <= 4) weighted -= 8.8 ether;
        return weighted / 2856;
    }

    function _roll(uint256 seed) private pure returns (uint256) {
        return uint32(EntropyLib.hash3(RngTags.BOX_BOON_LANE, seed, 0) >> 120) % PPM;
    }

    function _hits(uint256 seed, uint24 currentLevel) private returns (bool hit) {
        uint256 snapshot = vm.snapshotState();
        vm.recordLogs();
        boon.rollBoxBoons(boonId, CAP, 1, 10 ether, currentLevel, seed, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            bytes32 t = logs[i].topics[0];
            if (logs[i].emitter == ContractAddresses.GAME && (t == REWARD || t == WHALE_PASS || t == DISCARDED)) {
                hit = true;
            }
        }
        assertTrue(vm.revertToState(snapshot));
    }

    function _check(uint24 currentLevel, uint256 pinned) private {
        uint256 value = _fullUse(currentLevel);
        assertEq(value, pinned, "closed form");
        assertEq(boon.expectedPerBoon(currentLevel), value, "divisor is the full-use value");

        // The capped budget hits on rolls below 0.315 ETH / value, in ppm: the nearest seed
        // below the threshold hits and the nearest at or above it misses.
        uint256 threshold = CAP * PPM / value;
        uint256 below;
        uint256 belowRoll;
        uint256 above;
        uint256 aboveRoll = PPM;
        for (uint256 seed = 1; seed <= 6000; ++seed) {
            uint256 r = _roll(seed);
            if (r < threshold) {
                if (r >= belowRoll) (below, belowRoll) = (seed, r);
            } else if (r < aboveRoll) {
                (above, aboveRoll) = (seed, r);
            }
        }
        assertTrue(below != 0 && above != 0, "both sides of the threshold sampled");
        assertTrue(_hits(below, currentLevel), "roll just below 0.315 / value hits");
        assertFalse(_hits(above, currentLevel), "roll at or above 0.315 / value misses");
    }

    function test_FullUseDivisorAndCappedChance() public {
        _check(1, 315_147_058_823_529_411); // level 0
        _check(10, 410_392_156_862_745_098); // level 9
        _check(51, 533_753_501_400_560_224); // level 50
        _check(100, 1_022_997_198_879_551_820); // level 99
        _check(101, 410_392_156_862_745_098); // level 100
    }

    function test_CapNeverExceedsOneBoon() public pure {
        for (uint24 currentLevel = 1; currentLevel <= 300; ++currentLevel) {
            assertLe(CAP, _fullUse(currentLevel), "cap at or below one boon's full-use value");
        }
    }
}
