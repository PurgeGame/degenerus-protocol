// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

contract RangeDiffHarness is DegenerusGameStorage {
    function init(uint24 first, bool slotB) external { level = first - 1; ticketWriteSlot = slotB; }
    function award(bool candidate, uint32 id, uint24 first, uint24 count, uint24 stride, uint32 amount) external {
        if (candidate) _queueEntryRangeStridedCore(id, first, count, stride, amount, _mintCeiling(), false, ticketWriteSlot ? TICKET_SLOT_BIT : 0);
        else _referenceRange(id, first, count, stride, amount, _mintCeiling(), false, ticketWriteSlot ? TICKET_SLOT_BIT : 0);
    }
    function digest(uint24 first) external view returns (bytes32 result) {
        for (uint32 id = 1; id <= 2; ++id) {
            result = keccak256(abi.encode(result, ticketPending[id], farFutureOwed[id]));
        }
        for (uint24 lvl = first; lvl < first + 100; ++lvl) {
            uint24 key = lvl > _mintCeiling() ? _tqFarFutureKey(lvl) : _tqWriteKey(lvl);
            uint256[] storage q = ticketQueue[_ticketQueueStorageKey(key)];
            uint256 header;
            assembly ("memory-safe") { header := sload(q.slot) }
            result = keccak256(abi.encode(result, header, _tqWordAt(q, 0), _entryPacked(key, 1), _entryPacked(key, 2)));
        }
    }
    function _referenceRange(
        uint32 id,
        uint24 startLevel,
        uint24 numLevels,
        uint24 stride,
        uint32 entriesPerLevel,
        uint24 mintCeiling,
        bool rngLockedCached,
        uint24 writeSlotBit
    ) internal {
        // No liveness gate (see _queueEntries): post-liveness queued tickets are harmless.
        emit EntriesQueuedRange(id, startLevel, numLevels, stride, entriesPerLevel);
        // level / rngLockedFlag / ticketWriteSlot are loop-invariant and threaded in by the
        // caller (read once per award, not per stride-leg); none has a writer reachable from
        // this body, so the per-level lock check observes the same value either way.
        uint80 idBits = uint80(id) << OWNER_IDX_SHIFT;
        uint24 lvl = startLevel;
        for (uint24 i = 0; i < numLevels; ) {
            bool isFarFuture = lvl > mintCeiling;
            uint24 wk = isFarFuture ? _tqFarFutureKey(lvl) : (lvl | writeSlotBit);
            uint80 packed = _entryPacked(wk, id);
            uint32 owed = uint32(packed >> 8);
            uint8 rem = uint8(packed);
            if (packed == 0) {
                if (isFarFuture && rngLockedCached) revert RngLocked();
                packed = idBits;
                _tqAppend(wk, id);
            }
            owed = _addOwed(owed, entriesPerLevel, isFarFuture);
            _setEntryOwed(wk, id,
                (packed & OWNER_IDX_MASK) | (uint80(owed) << 8) | uint80(rem));

            unchecked {
                lvl += stride;
                ++i;
            }
        }
    }

}

contract RangeAwardDifferentialTest is Test {
    function testFuzz_RangeStateMatches(uint24 first, uint8 stride, uint8 count, uint32 initial, uint32 amount, bool slotB) public {
        first = uint24(bound(first, 1, 300));
        stride = uint8(bound(stride, 1, 4));
        count = uint8(bound(count, 1, 100 / stride));
        RangeDiffHarness old = new RangeDiffHarness();
        RangeDiffHarness next = new RangeDiffHarness();
        old.init(first, slotB);
        next.init(first, slotB);
        // Seed the shared words with a different pattern and another owner's balances.
        old.award(false, 1, first, 25, 4, initial);
        next.award(false, 1, first, 25, 4, initial);
        old.award(false, 2, first, 25, 4, 11);
        next.award(false, 2, first, 25, 4, 11);
        old.award(false, 1, first, count, stride, amount);
        next.award(true, 1, first, count, stride, amount);
        assertEq(next.digest(first), old.digest(first));
    }
}
