// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameGameOverModule} from "../../contracts/modules/DegenerusGameGameOverModule.sol";

/// @dev The independent reference below is the tally at 20a0e892, before gas changes.
///      Compare the production entry against it from the same seeded storage snapshot.
contract DeadVrfTallyParityHarness is DegenerusGameGameOverModule {
    function seed(uint256 count, uint256 salt, uint8 shift, uint8 stage) external {
        snapShift = shift;
        for (uint256 i; i < count; ++i) {
            uint80 packed = uint80(uint256(keccak256(abi.encode(salt, i))));
            lvlEntryOwner[5].push(EntryOwner(address(uint160(i + 1)), packed));
        }
        foilDrainDay = 11;
        foilLastResolveDay = 14;
        foilCursor = 1;
        for (uint24 day = 11; day <= 14; ++day) {
            if (day == 13) continue; // Include an empty day between populated ones.
            for (uint256 i; i < 7; ++i) {
                foilBuyers[day].push((uint256(i % 2 == 0 ? 5 : 6) << 160) | uint160(i + 1));
            }
        }
        lvlTraitEntry[5][0].push(1);
        lvlTraitEntry[5][255].push(1);
        deadTallyStage = stage;
        if (stage != 0) {
            deadTallyPos = uint32(count);
            deadTallyFoilDay = 11;
            deadTallyFoilIdx = 1;
        }
    }

    function seedOne(uint80 packed, uint8 shift) external {
        snapShift = shift;
        lvlEntryOwner[5].push(EntryOwner(address(1), packed));
    }

    function legacyTally(uint24 lvl) external returns (bool finished) {
        uint256 stage = deadTallyStage;
        if (stage == 3) return true;
        uint256 units = 3000; // Pinned reference batch budget.
        uint256 uncreated = deadUncreated;
        uint24 dd = deadTallyFoilDay;
        uint256 idx = deadTallyFoilIdx;

        if (stage == 0) {
            uint256 len = lvlEntryOwner[lvl].length;
            uint256 pos = deadTallyPos;
            uint8 shift = _snapShiftFor(lvl);
            while (pos < len) {
                if (units == 0) {
                    deadTallyPos = uint32(pos);
                    deadUncreated = uint64(uncreated);
                    return false;
                }
                unchecked {
                    --units;
                    ++pos;
                }
                // pos is now the registry position plus one, the form _entryRecord takes.
                uncreated += _legacyWeight(uint80(_entryRecord(lvl, uint32(pos)) >> 160), shift);
            }
            deadTallyPos = uint32(pos);
            stage = 1;
            // The foil walk starts at the drain's own low-water mark.
            dd = foilDrainDay;
            idx = foilCursor;
        }

        if (stage == 1) {
            uint24 last = foilLastResolveDay;
            while (dd != 0 && dd <= last) {
                uint256[] storage bucket = foilBuyers[dd];
                uint256 n = bucket.length;
                while (idx < n) {
                    if (units == 0) {
                        _legacySave(1, dd, idx, uncreated);
                        return false;
                    }
                    unchecked {
                        --units;
                    }
                    if (uint24(bucket[idx] >> 160) == lvl) {
                        uncreated += FOIL_PACK_ENTRIES * QTY_SCALE;
                    }
                    unchecked {
                        ++idx;
                    }
                }
                // Charge the day step too, so a long run of empty days stays metered.
                if (units == 0) {
                    _legacySave(1, dd, idx, uncreated);
                    return false;
                }
                unchecked {
                    --units;
                    ++dd;
                }
                idx = 0;
            }
            stage = 2;
        }

        // Stage 2: the 256 bucket lengths, in one call once enough units remain.
        if (units < 256) {
            _legacySave(2, dd, idx, uncreated);
            return false;
        }
        uint256 created;
        uint256 traits;
        for (uint256 t; t < 256; ) {
            uint256 n = lvlTraitEntry[lvl][t].length;
            if (n != 0) {
                created += n;
                unchecked {
                    ++traits;
                }
            }
            unchecked {
                ++t;
            }
        }
        deadCreated = uint64(created);
        deadTraitCount = uint16(traits);
        _legacySave(3, dd, idx, uncreated);
        return true;
    }

    /// @dev Persist a paused (or finished) tally.
    function _legacySave(uint256 stage, uint24 dd, uint256 idx, uint256 uncreated) private {
        deadTallyStage = uint8(stage);
        deadTallyFoilDay = dd;
        deadTallyFoilIdx = uint32(idx);
        deadUncreated = uint64(uncreated);
    }

    /// @dev An owed word's uncreated weight in QTY_SCALE units, snap-adjusted exactly as the
    ///      ticket drain applies it on first touch (_processOneTicketEntry).
    function _legacyWeight(uint80 packed, uint8 shift) private pure returns (uint256) {
        if (shift != 0 && packed != 0 && packed & SNAP_DONE_BIT == 0) {
            packed = _snapOwedPacked(packed, shift);
        }
        return uint256(uint32(packed >> 8)) * QTY_SCALE + uint8(packed);
    }

}

contract DeadVrfTallyParityTest is Test {
    DeadVrfTallyParityHarness private h;

    function setUp() public {
        h = new DeadVrfTallyParityHarness();
    }

    function _observe(bool legacy) private returns (bool done, bytes32 writes) {
        vm.startStateDiffRecording();
        done = legacy ? h.legacyTally(5) : h.tallyDeadVrf(5);
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        for (uint256 i; i < accesses.length; ++i) {
            for (uint256 j; j < accesses[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory a = accesses[i].storageAccesses[j];
                if (a.isWrite) writes = keccak256(abi.encode(writes, a.account, a.slot, a.previousValue, a.newValue));
            }
        }
    }

    function _compare() private {
        uint256 snapshot = vm.snapshotState();
        (bool oldDone, bytes32 oldWrites) = _observe(true);
        assertTrue(vm.revertToStateAndDelete(snapshot));
        (bool done, bytes32 writes) = _observe(false);
        assertEq(done, oldDone, "same completion and pause boundary");
        assertEq(writes, oldWrites, "identical ordered storage writes and values");
    }

    function testFuzz_WeightMatchesSnapPacking(uint80 packed, uint8 shift) public {
        h.seedOne(packed, shift);
        _compare();
    }

    function testFuzz_MixedStagesMatch(uint8 count, uint256 salt, uint8 shift, uint8 stage) public {
        h.seed(count, salt, shift, uint8(bound(stage, 0, 3)));
        _compare();
    }

    function test_ResumeAfterFullRegistryBatch() public {
        h.seed(3001, 777, 3, 0);
        _compare();
        _compare();
    }

    function test_ExactRegistryBudgetThenFoilContinuation() public {
        h.seed(3000, 888, 1, 0);
        _compare();
        _compare();
    }

    function test_TraitScanDefersAtBudgetBoundary() public {
        h.seed(2800, 999, 4, 0);
        _compare();
        _compare();
    }
}
