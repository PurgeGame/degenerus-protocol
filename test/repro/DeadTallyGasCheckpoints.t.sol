// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameGameOverModule} from "../../contracts/modules/DegenerusGameGameOverModule.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

contract DeadTallyCheckpointHarness is DegenerusGameGameOverModule, BucketSeed {
    function seed(uint24 lvl, uint256 count) external {
        level = lvl;
        uint24 key = _tqReadKey(lvl);
        for (uint256 i; i < count; ++i) _seedQueued(key, lvl, address(uint160(0x10000 + i)), uint80(100) << 8);
    }
    function tallyState() external view returns (uint8 stage, uint32 pos, uint64 uncreated) {
        return (deadTallyStage, deadTallyPos, deadUncreated);
    }
}

contract DeadTallyGasCheckpointsTest is Test {
    function test_ColdTallyCheckpointsBelow10MAndLowGasHasSameWeight() public {
        DeadTallyCheckpointHarness h = new DeadTallyCheckpointHarness();
        h.seed(110, 3000);
        uint256 snap = vm.snapshotState();
        bool done;
        uint256 calls;
        while (!done && calls++ < 20) {
            vm.cool(address(h));
            uint256 start = gasleft();
            done = h.tallyDeadVrf{gas: 10_000_000}(110);
            uint256 used = start - gasleft() + 21_000;
            emit log_named_uint("cold deterministic tally including intrinsic", used);
            assertLt(used, 10_000_000);
        }
        assertTrue(done);
        assertGt(calls, 1, "cold backlog spans checkpoints");
        (uint8 stage,, uint64 weight) = h.tallyState();
        assertEq(stage, 3);
        assertEq(weight, 3000 * 100 * 100);
        assertTrue(vm.revertToState(snap));
        done = false;
        calls = 0;
        while (!done && calls++ < 30) {
            vm.cool(address(h));
            done = h.tallyDeadVrf{gas: 2_000_000}(110);
        }
        assertTrue(done);
        uint64 splitWeight;
        (stage,, splitWeight) = h.tallyState();
        assertEq(stage, 3);
        assertEq(splitWeight, weight);
    }
}
