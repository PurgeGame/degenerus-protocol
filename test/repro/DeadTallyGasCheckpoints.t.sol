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

    function seedCreated(uint24 lvl, uint256 live, uint256 salt)
        external returns (uint256 expectedCreated, uint256 expectedTraits)
    {
        _setTicketBufferLevel(lvl);
        traitBucketLive[lvl & 1] = live;
        uint256 base = _traitBufferBase(lvl);
        for (uint256 t; t < 256; ++t) {
            // Include live zero-count buckets and nonzero dead backing words.
            uint256 count = t % 8 == 0 ? 0 : uint32(uint256(keccak256(abi.encode(salt, t))));
            if (t == 255) count = type(uint32).max;
            uint256 header = (uint256(0xabcdef) << 32) | count;
            assembly ("memory-safe") { sstore(add(base, t), header) }
            if (live & (uint256(1) << t) != 0 && count != 0) {
                expectedCreated += count;
                ++expectedTraits;
            }
        }
        deadTallyStage = 2;
    }

    function createdState() external view returns (uint64 created, uint16 traits) {
        return (deadCreated, deadTraitCount);
    }
}

contract DeadTallyGasCheckpointsTest is Test {
    function testFuzz_CreatedTallyUsesOnlyLiveCounts(uint256 live, uint256 salt) public {
        _checkCreated(live, salt);
    }

    function test_CreatedTallyEmptyAndFullBitmap() public {
        _checkCreated(0, 1);
        _checkCreated(type(uint256).max, 2);
    }

    function _checkCreated(uint256 live, uint256 salt) private {
        DeadTallyCheckpointHarness h = new DeadTallyCheckpointHarness();
        (uint256 expectedCreated, uint256 expectedTraits) = h.seedCreated(110, live, salt);
        vm.cool(address(h));
        uint256 start = gasleft();
        assertTrue(h.tallyDeadVrf{gas: 1_100_000}(110));
        assertLt(start - gasleft(), 1_100_000, "full scan fits existing admission bound and tail");
        (uint64 created, uint16 traits) = h.createdState();
        assertEq(created, expectedCreated, "counts ignore dead backing words and upper header bits");
        assertEq(traits, expectedTraits, "live zero-count bucket is not a populated trait");
    }

    function test_CreatedTallyRejectsRetiredLevelAndIgnoresFutureAlias() public {
        DeadTallyCheckpointHarness h = new DeadTallyCheckpointHarness();
        h.seedCreated(110, type(uint256).max, 3);
        vm.expectRevert(bytes4(keccak256("E()")));
        h.tallyDeadVrf(108);
        (uint8 stage,,) = h.tallyState();
        assertEq(stage, 2, "retired level cannot finish the tally");
        assertTrue(h.tallyDeadVrf(112));
        (uint64 created, uint16 traits) = h.createdState();
        assertEq(created, 0, "future level must not read the retained level's counts");
        assertEq(traits, 0);
    }

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
