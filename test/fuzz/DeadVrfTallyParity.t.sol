// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameGameOverModule} from "../../contracts/modules/DegenerusGameGameOverModule.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

/// @dev The independent reference below is the tally at 20a0e892, before gas changes.
///      Compare the production terminal worker against it from the same seeded storage snapshot.
contract DeadVrfTallyParityHarness is DegenerusGameGameOverModule, WalletSeed {
    /// @dev The deterministic ending is latched on the passed terminal level and its payout is
    ///      marked settled, so each terminal call (`runGameOverAdvance`, mineFlip's Terminal stage)
    ///      runs exactly the tally and stops at its boundary instead of continuing into the payout.
    ///      The tally reads none of these fields. The dead latch is the one `_latchDeadEnding`
    ///      writes (callback authority revoked, publication cleared, word waiting); past the
    ///      14-day VRF-dead window it makes the ending live.
    function latchDeadTally() external {
        _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, 1);
        _lrWrite(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK, 1);
        _setRngRequestActive(false);
        _setRngSessionPublished(false);
        rngWordCurrent = RNG_WORD_WAITING;
        _goWrite(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK, 1);
    }

    function tallyStage() external view returns (uint8) { return deadTallyStage; }
    function seed(uint256 count, uint256 salt, uint8 shift, uint8 stage) external {
        snapShift = shift;
        for (uint256 i; i < count; ++i) {
            uint80 packed = uint80(uint256(keccak256(abi.encode(salt, i))));
            uint80 bits = (uint80(_seedWallet(address(uint160(i + 1)))) << OWNER_IDX_SHIFT);
            _tqAppend(_tqReadKey(5), uint32(bits >> OWNER_IDX_SHIFT));
            _setEntryOwed(_tqReadKey(5), uint32(bits >> OWNER_IDX_SHIFT), bits | (packed & ((uint80(1) << 41) - 1)));
        }
        foilGenerationDay = 0;
        foilFirstDrawDay = 0;
        foilCursor = 1;
        foilWriteCount = 7;
        foilReadCount = 7;
        for (uint24 day; day < 2; ++day) {
            for (uint256 i; i < 7; ++i) {
                uint256 pack = (uint256(i % 2 == 0 ? 5 : 6) << 160) | uint160(i + 1);
                uint256 packSlot = _foilSlot(day, i);
                assembly ("memory-safe") { sstore(packSlot, pack) }
            }
        }
        _setTicketBufferLevel(5);
        _bucketAppendRun(_traitBufferBase(5), 0, 1, 1, 5);
        _bucketAppendRun(_traitBufferBase(5), 255, 1, 1, 5);
        deadTallyStage = stage;
        if (stage != 0) {
            deadTallyPos = uint32(count);
            deadTallyFoilDay = 1;
            deadTallyFoilIdx = _foilReadKey() == 0 ? foilCursor : 0;
        }
    }

    function seedOne(uint80 packed, uint8 shift) external {
        snapShift = shift;
        uint80 bits = (uint80(_seedWallet(address(1))) << OWNER_IDX_SHIFT);
        _tqAppend(_tqReadKey(5), uint32(bits >> OWNER_IDX_SHIFT));
        _setEntryOwed(_tqReadKey(5), uint32(bits >> OWNER_IDX_SHIFT), bits | (packed & ((uint80(1) << 41) - 1)));
    }

    function tallyDigest() external view returns (bytes32) {
        return keccak256(abi.encode(deadTallyStage, deadTallyPos, deadTallyFoilDay,
            deadTallyFoilIdx, deadUncreated, deadCreated, deadTraitCount));
    }

    function legacyTally(uint24 lvl) external returns (bool finished) {
        uint256 stage = deadTallyStage;
        if (stage == 3) return true;
        uint256 units = 2800; // Pinned reference batch budget.
        uint256 uncreated = deadUncreated;
        uint24 dd = deadTallyFoilDay;
        uint256 idx = deadTallyFoilIdx;

        if (stage == 0) {
            uint256 len = _ticketQueueLength(_tqReadKey(lvl));
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
                uncreated += _legacyWeight(uint80(_entryRecordOf(_tqReadKey(lvl), uint32(pos)) >> 160), shift);
            }
            deadTallyPos = 0;
            stage = 1;
            // The foil walk starts at the drain's own low-water mark.
            dd = 1;
            idx = _foilReadKey() == 0 ? foilCursor : 0;
        }

        if (stage == 1) {
            uint24 last = 2;
            while (dd != 0 && dd <= last) {
                uint256 n = _foilCount(dd - 1);
                while (idx < n) {
                    if (units == 0) {
                        _legacySave(1, dd, idx, uncreated);
                        return false;
                    }
                    unchecked {
                        --units;
                    }
                    uint256 pack;
                    {
                        uint256 packSlot = _foilSlot(dd - 1, idx);
                        assembly ("memory-safe") { pack := sload(packSlot) }
                    }
                    if (uint24(pack >> 160) == lvl) {
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
                idx = dd <= 2 && dd - 1 == _foilReadKey() ? foilCursor : 0;
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
            uint256 n = _bucketLength(lvl, t);
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
        // Past the 14-day VRF-dead window from a zero request time.
        vm.warp(30 days);
        h = new DeadVrfTallyParityHarness();
        h.latchDeadTally();
    }

    /// @dev One production terminal call (mineFlip's Terminal stage worker) with `callGas` as its
    ///      gas and allowance; true once the tally is done.
    function _tally(uint256 callGas) private returns (bool) {
        h.runGameOverAdvance{gas: callGas}(0, 5, callGas);
        return h.tallyStage() == 3;
    }

    function _observe(bool legacy) private returns (bool done, bytes32 writes) {
        vm.startStateDiffRecording();
        done = legacy ? h.legacyTally(5) : _tally(gasleft() - 50_000);
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

    /// @dev The reference's 2,800-unit pauses are historical. Compare completed
    ///      accounting while the production implementation stops on actual gas.
    function _compareCompleted(uint256 callGas) private {
        uint256 snapshot = vm.snapshotState();
        bool done;
        for (uint256 i; i < 8 && !done; ++i) done = h.legacyTally(5);
        assertTrue(done, "reference completes");
        bytes32 expected = h.tallyDigest();
        assertTrue(vm.revertToStateAndDelete(snapshot));
        done = false;
        uint256 calls;
        while (!done && calls < 64) {
            vm.cool(address(h));
            done = _tally(callGas);
            ++calls;
        }
        assertTrue(done, "gas-checkpointed tally completes");
        assertGt(calls, 1, "cold tally spans actual gas checkpoints");
        assertEq(h.tallyDigest(), expected, "same completed counters and ticket weight");
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
        _compareCompleted(2_000_000);
    }

    function test_ExactRegistryBudgetThenFoilContinuation() public {
        h.seed(2800, 888, 1, 0);
        _compareCompleted(2_000_000);
    }

    function test_TraitScanDefersAtBudgetBoundary() public {
        h.seed(2800, 999, 4, 0);
        _compareCompleted(1_100_000);
    }
}
