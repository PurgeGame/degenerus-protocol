// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

contract PassAwardBatchHarness is DegenerusGameStorage {
    function award(address buyer, uint24 start, uint24 span, uint256 amount) external {
        _queueHalfPassAward(buyer, start, span, amount);
    }
    function range(address buyer, uint24 start, uint24 count, uint24 stride, uint32 amount) external {
        _queueEntryRangeStridedCore(buyer, start, count, stride, amount, _mintCeiling(), rngLockedFlag,
            ticketWriteSlot ? TICKET_SLOT_BIT : uint24(0));
    }
    function configure(uint24 lvl, uint24 early, bool locked, bool writeSlot) external {
        level = lvl;
        earlyTicketLevel = early;
        rngLockedFlag = locked;
        ticketWriteSlot = writeSlot;
    }
    function capacity() external {
        assembly ("memory-safe") { sstore(ticketOwners.slot, 3000000000) }
    }
    function seed(address buyer, uint24 lvl, uint32 amount, bool snapped) external {
        _queueEntries(buyer, lvl, amount, true);
        if (snapped) {
            uint24 key = lvl > _mintCeiling() ? _tqFarFutureKey(lvl) : _tqWriteKey(lvl);
            uint80 packed = _entriesOwed(key, buyer);
            _setEntryOwed(key, uint32(packed >> OWNER_IDX_SHIFT), packed | SNAP_DONE_BIT);
        }
    }
    function recycled(address buyer, uint24 lvl, uint32 amount) external {
        // Retire a physical queue while retaining its old lane, as production recycling does.
        _queueEntries(buyer, lvl, amount, true);
        _releaseTicketQueue(_tqFarFutureKey(lvl));
    }
    function oracleRange(address buyer, uint24 start, uint24 count, uint24 stride, uint32 amount, bool bypass) external {
        _oracleRange(buyer, start, count, stride, amount, bypass, _mintCeiling(), rngLockedFlag,
            ticketWriteSlot ? TICKET_SLOT_BIT : uint24(0));
    }
    // Frozen pre-optimization traversal: each original leg uses the original per-level sink.
    function oracleAward(address buyer, uint24 start, uint24 span, uint256 amount, bool bypass) external {
        uint24 ceiling = _mintCeiling();
        bool locked = rngLockedFlag;
        uint24 writeSlot = ticketWriteSlot ? TICKET_SLOT_BIT : uint24(0);
        uint32 base = uint32((amount / 4) * 4);
        if (base != 0) _oracleRange(buyer, start, span, 1, base, bypass, ceiling, locked, writeSlot);
        uint256 rem = amount % 4;
        if (rem == 0) return;
        if (rem >= 2) _oracleRange(buyer, start, (span + 1) / 2, 2, 4, bypass, ceiling, locked, writeSlot);
        if (rem == 1) _oracleRange(buyer, start, (span + 3) / 4, 4, 4, bypass, ceiling, locked, writeSlot);
        else if (rem == 3) _oracleRange(buyer, start + 1, (span + 2) / 4, 4, 4, bypass, ceiling, locked, writeSlot);
    }
    function _oracleRange(address buyer, uint24 start, uint24 count, uint24 stride, uint32 amount,
        bool bypass, uint24 ceiling, bool locked, uint24 writeSlot) private {
        emit EntriesQueuedRange(buyer, start, count, stride, amount);
        uint24 lvl = start;
        for (uint24 i; i < count;) {
            bool far = lvl > ceiling;
            uint24 key = far ? _tqFarFutureKey(lvl) : (lvl | writeSlot);
            uint80 packed = _entriesOwed(key, buyer);
            uint32 owed = uint32(packed >> 8);
            uint8 rem = uint8(packed);
            bool room = true;
            if (packed == 0) {
                if (far && locked && !bypass) revert RngLocked();
                packed = _registerEntryOwner(buyer, lvl);
                room = packed != 0;
                if (!room && !bypass) revert E();
                if (room) _tqAppend(key, uint32(packed >> OWNER_IDX_SHIFT));
            }
            if (room) {
                owed = _addOwed(owed, amount, far);
                _setEntryOwed(key, uint32(packed >> OWNER_IDX_SHIFT),
                    (packed & OWNER_IDX_MASK) | (uint80(owed) << 8) | uint80(rem));
            }
            unchecked { lvl += stride; ++i; }
        }
    }
}

contract PassAwardBatchTest is Test {
    PassAwardBatchHarness internal h;
    address internal constant BUYER = address(0xB071);
    function setUp() public { h = new PassAwardBatchHarness(); }

    function _equivalent(bytes memory beforeCall, bytes memory afterCall) internal {
        uint256 snapshot = vm.snapshotState();
        vm.record();
        vm.recordLogs();
        (bool beforeOk, bytes memory beforeResult) = address(h).call(beforeCall);
        Vm.Log[] memory beforeLogs = vm.getRecordedLogs();
        (, bytes32[] memory writes) = vm.accesses(address(h));
        bytes32[] memory values = new bytes32[](writes.length);
        for (uint256 i; i < writes.length; ++i) values[i] = vm.load(address(h), writes[i]);
        assertTrue(vm.revertToState(snapshot));
        vm.record();
        vm.recordLogs();
        (bool afterOk, bytes memory afterResult) = address(h).call(afterCall);
        Vm.Log[] memory afterLogs = vm.getRecordedLogs();
        (, bytes32[] memory afterWrites) = vm.accesses(address(h));
        assertEq(afterOk, beforeOk, "success parity");
        assertEq(afterResult, beforeResult, "return/revert parity");
        assertEq(keccak256(abi.encode(afterLogs)), keccak256(abi.encode(beforeLogs)), "ordered logs");
        for (uint256 i; i < writes.length; ++i) assertEq(vm.load(address(h), writes[i]), values[i], "written word");
        for (uint256 i; i < afterWrites.length; ++i) {
            bool found;
            for (uint256 j; j < writes.length; ++j) if (afterWrites[i] == writes[j]) { found = true; break; }
            assertTrue(found, "no new storage location");
        }
    }
    function _award(address buyer, uint24 start, uint24 span, uint256 amount) internal {
        _equivalent(abi.encodeCall(h.oracleAward, (buyer, start, span, amount, false)),
            abi.encodeCall(h.award, (buyer, start, span, amount)));
    }
    function testFuzzAward(uint24 seed, uint8 spanSeed, uint32 amount, uint32 existing, bool locked,
        bool writeSlot, uint8 remSeed) public {
        uint24 lvl = uint24(bound(seed, 1, 900));
        uint24 start = lvl + 1;
        uint24 span = uint24(bound(spanSeed, 0, 100));
        h.configure(lvl, 0, false, writeSlot);
        // Include near/far transition, uint32 rollover, saturation and snap flags.
        h.seed(BUYER, start, existing, remSeed & 1 != 0);
        if (span > 1) h.seed(BUYER, start + span - 1, existing, remSeed & 2 != 0);
        h.configure(lvl, 0, locked, writeSlot);
        _award(BUYER, start, span, amount);
    }
    function testFuzzStrided(uint24 seed, uint8 countSeed, uint8 strideSeed, uint32 amount, bool locked,
        bool writeSlot) public {
        uint24 lvl = uint24(bound(seed, 1, 900));
        uint24 stride = uint24(bound(strideSeed, 1, 4));
        uint24 count = uint24(bound(countSeed, 0, 100 / stride));
        h.configure(lvl, 0, false, writeSlot);
        h.seed(BUYER, lvl + 1, 17, true);
        h.configure(lvl, 0, locked, writeSlot);
        _equivalent(abi.encodeCall(h.oracleRange, (BUYER, lvl + 1, count, stride, amount, false)),
            abi.encodeCall(h.range, (BUYER, lvl + 1, count, stride, amount)));
    }
    function testRecycledFarWordTags() public {
        h.configure(100, 0, false, false);
        for (uint24 i = 105; i <= 200; ++i) h.recycled(BUYER, i, 9123);
        h.configure(200, 0, false, false);
        _award(BUYER, 201, 100, 7);
    }
    function testEarlyPoolCeiling() public {
        h.configure(24, 26, false, true);
        h.seed(BUYER, 25, type(uint32).max - 1, true);
        h.seed(BUYER, 26, 19, false);
        _award(BUYER, 25, 100, 7);
    }
    function testLockedExistingFarLanesCanTopUp() public {
        h.configure(24, 0, false, false);
        h.award(BUYER, 25, 100, 4);
        h.configure(24, 0, true, false);
        _award(BUYER, 25, 100, 7);
    }
    function testPreserveUnrelatedOwnerAndOutsideLanes() public {
        h.configure(100, 0, false, false);
        for (uint24 i = 102; i <= 109; ++i) {
            h.seed(address(0xABCD), i, 9123, true);
            h.seed(BUYER, i, 400, true);
        }
        _award(BUYER, 105, 3, 7);
    }
    function testTruncatedBaseKeepsStridedSemantics() public {
        _award(BUYER, 1, 100, (uint256(1) << 32) + 3);
    }
    function testTruncatedBaseWithRemainder() public {
        _award(BUYER, 1, 100, (uint256(1) << 32) + 7);
    }
    function testCapacityPurchaseReverts() public { h.capacity(); _award(BUYER, 1, 100, 7); }
    function testZeroBuyerPurchase() public { _award(address(0), 1, 100, 7); }
    function testFarQueueCollisionReverts() public {
        h.configure(100, 0, false, false);
        h.seed(BUYER, 150, 99, false);
        h.configure(200, 0, false, false);
        _award(BUYER, 201, 100, 7);
    }
}
