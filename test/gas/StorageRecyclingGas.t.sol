// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;
import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

contract RecyclingGasHarness is DegenerusGameStorage {
    function seed(bool payload) external {
        _setTicketBufferLevel(1);
        level = 2;
        if (payload) _bucketAppendRun(_traitBufferBase(1), 7, 1, 1024, 1);
    }
    function prepare() external returns (bool) { return _prepareTicketLevel(3); }
    function append() external { _bucketAppendRun(_traitBufferBase(3), 7, 2, 1024, 3); }
    function seedConsumedQueues(uint256 count) external {
        address[] storage boxes = boxPlayers[_rngReadBuffer()];
        uint256[] storage bets = degeneretteQueue[_rngReadBuffer()];
        assembly ("memory-safe") {
            sstore(boxes.slot, count)
            mstore(0, boxes.slot)
            sstore(keccak256(0, 32), 0xB011)
            sstore(bets.slot, count)
            mstore(0, bets.slot)
            sstore(keccak256(0, 32), 0xB022)
        }
    }
    function sealQueues() external {
        require(_lootboxReadComplete());
        _swapRngBuffers();
        _resetLootboxWriteBuffer(_rngWriteBuffer());
    }
    function queueState() external view returns(uint256 boxes, uint256 bets, uint256 backing) {
        address[] storage b = boxPlayers[_rngWriteBuffer()];
        uint256[] storage d = degeneretteQueue[_rngWriteBuffer()];
        boxes = b.length; bets = d.length;
        assembly ("memory-safe") { mstore(0, d.slot) backing := sload(keccak256(0, 32)) }
    }
    function huge() external { lvlTraitEntry[1][7] = 1_000_000; traitBucketLive[1] |= uint256(1) << 7; }
}

/// @dev Run with FOUNDRY_ISOLATE=true: setup, reset and append are separate cold calls.
contract StorageRecyclingGasTest is Test {
    RecyclingGasHarness fresh;
    RecyclingGasHarness reused;
    function setUp() public {
        fresh = new RecyclingGasHarness();
        reused = new RecyclingGasHarness();
        fresh.seed(false);
        reused.seed(true);
    }
    function test_ColdNonzeroBackingReuseSavesGas() public {
        assertTrue(fresh.prepare());
        assertTrue(reused.prepare());
        fresh.append();
        uint256 freshGas = vm.snapshotGasLastCall("fresh-1024-occurrences");
        reused.append();
        uint256 reuseGas = vm.snapshotGasLastCall("reused-1024-occurrences");
        emit log_named_uint("fresh append gas", freshGas);
        emit log_named_uint("reused append gas", reuseGas);
        assertGt(freshGas, reuseGas + 1_000_000, "net savings after stamped-header overhead");
    }
    function test_QueueSealGasIndependentOfMillionLengthsAndLeavesBackingIntact() public {
        fresh.seedConsumedQueues(1); reused.seedConsumedQueues(1_000_000);
        fresh.sealQueues(); uint256 small = vm.snapshotGasLastCall("one-entry-queue-seal");
        reused.sealQueues(); uint256 huge = vm.snapshotGasLastCall("million-entry-queue-seal");
        emit log_named_uint("one-entry queue seal gas", small);
        emit log_named_uint("million-entry queue seal gas", huge);
        assertLt(huge, 100_000);
        assertLt(small > huge ? small - huge : huge - small, 5_000);
        (uint256 boxes, uint256 bets, uint256 backing) = reused.queueState();
        assertEq(boxes, 0); assertEq(bets, 0); assertEq(backing, 0xB022, "no element-by-element clear");
    }
    function test_ResetGasIndependentOfMillionCount() public {
        reused.huge();
        assertTrue(fresh.prepare());
        uint256 small = vm.snapshotGasLastCall("small-reset");
        assertTrue(reused.prepare());
        uint256 huge = vm.snapshotGasLastCall("million-reset");
        emit log_named_uint("small reset gas", small);
        emit log_named_uint("million reset gas", huge);
        assertLt(huge, 50_000);
        assertLt(small > huge ? small - huge : huge - small, 5_000);
    }
}
