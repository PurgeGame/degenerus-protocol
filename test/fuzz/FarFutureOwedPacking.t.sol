// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract FuturePackingHarness is DegenerusGameStorage, WalletSeed {
    function write(address p, uint24 key, uint32 owed, uint8 rem, bool snapped) external {
        if (key & TICKET_FAR_FUTURE_BIT != 0) _bindTicketQueue(key);
        uint80 owner = (uint80(_seedWallet(p)) << OWNER_IDX_SHIFT);
        uint80 value = owed == 0 && rem == 0 && !snapped ? 0
            : owner | (uint80(owed) << 8) | uint80(rem) | (snapped ? SNAP_DONE_BIT : uint80(0));
        _setEntryOwed(key, uint32(owner >> OWNER_IDX_SHIFT), value);
    }
    function read(address p, uint24 key) external view returns (uint80) { return _owedOf(key, p); }
    function total(address p, uint24 lvl) external view returns (uint32) { return _entriesOwedTotal(lvl, _walletIdOf(p)); }
    function credit(address p, uint24 lvl, uint32 n) external { _queueEntries(_seedWallet(p), lvl, n, false); }
    function creditScaled(address p, uint24 lvl, uint32 n) external { _queueEntriesScaled(_seedWallet(p), lvl, n); }
    function range(address p, uint24 lvl, uint24 n, uint24 stride, uint32 amount) external {
        _queueEntryRangeStridedCore(_seedWallet(p), lvl, n, stride, amount, _mintCeiling(), rngLockedFlag,
            ticketWriteSlot ? TICKET_SLOT_BIT : uint24(0));
    }
    function consume(uint24 key) external {
        uint256[] storage q = ticketQueue[_ticketQueueStorageKey(key)];
        uint256 n = _ticketQueueLength(key);
        for (uint256 i; i < n; ++i) _setEntryOwed(key, _tqPositionAt(q, i), 0);
        _releaseTicketQueue(key);
    }
    function setLevel(uint24 lvl) external { level = lvl; }
    function lock() external { rngLockedFlag = true; }
    function length(uint24 lvl) external view returns (uint256) { return _ticketQueueLength(_tqFarFutureKey(lvl)); }
    function legacy(address p, uint24 lvl) external view returns (uint256) {
        return ticketPending[_walletIdOf(p)];
    }
    function blockWord(address p, uint24 lvl) external view returns (uint256) {
        return farFutureOwed[_walletIdOf(p)][((lvl - 1) % 100) >> 3];
    }
    function roots() external pure returns (uint256 legacySlot, uint256 packedSlot) {
        assembly ("memory-safe") { legacySlot := ticketPending.slot packedSlot := farFutureOwed.slot }
    }
}

contract FarFutureOwedPackingTest is Test {
    FuturePackingHarness private h;
    address private constant A = address(0xA11CE);
    address private constant B = address(0xB0B);
    uint24 private constant FF = 1 << 22;
    uint24 private constant SLOT = 1 << 23;
    uint80 private constant SNAP = uint80(1) << 40;
    uint32 private constant CAP = (1 << 30) - 1;

    function setUp() public { h = new FuturePackingHarness(); }

    function test_AppendedRootAndEightLanes() public {
        (uint256 oldRoot, uint256 newRoot) = h.roots();
        assertEq(oldRoot, 78);
        assertEq(newRoot, 81);
        h.range(A, 9, 8, 1, 4);
        uint256 expected;
        for (uint24 i; i < 8; ++i) {
            expected |= uint256(0x80000004) << (32 * i);
            assertEq(h.length(9 + i), 1);
            assertEq(h.legacy(A, 9 + i), 0);
        }
        assertEq(h.blockWord(A, 9), expected);
    }

    function testFuzz_EightLanesAndOtherOwnerRemainIndependent(uint32[8] memory owed, uint8 changed) public {
        changed %= 8;
        for (uint24 i; i < 8; ++i) {
            h.write(A, (9 + i) | FF, owed[i], 0, false);
            h.write(B, (9 + i) | FF, 4, 0, false);
        }
        h.write(A, (9 + uint24(changed)) | FF, owed[changed], 0, true);
        for (uint24 i; i < 8; ++i) {
            uint80 value = h.read(A, (9 + i) | FF);
            uint32 expected = owed[i] > CAP ? CAP : owed[i];
            assertEq(uint32(value >> 8), expected);
            assertEq(uint8(value), 0);
            assertEq(value & SNAP, i == changed ? SNAP : 0);
            assertEq(h.total(A, 9 + i), expected);
            assertEq(uint32(h.read(B, (9 + i) | FF) >> 8), 4);
        }
    }

    function test_CappedWriteAndClearPreserveOtherCohorts() public {
        h.write(A, 9, 11, 21, false);
        h.write(A, 9 | SLOT, 12, 22, false);
        h.write(A, 8 | FF, 5, 0, false);
        h.write(A, 9 | FF, uint32(1 << 30), 0, false);
        assertEq(h.total(A, 9), CAP + 23);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        h.write(A, 9 | FF, 7, 50, true);
        h.write(A, 9 | FF, 7, 0, true);
        assertEq(h.total(A, 9), 30);
        assertEq(uint32(h.read(A, 9) >> 8), 11);
        h.write(A, 9 | FF, 0, 0, false);
        assertEq(h.total(A, 9), 23);
        assertEq(uint8(h.read(A, 9)), 21);
        assertEq(uint8(h.read(A, 9 | SLOT)), 22);
        assertEq(uint32(h.read(A, 8 | FF) >> 8), 5);
    }

    function test_AddPastCapPreservesBothNeighborLanes() public {
        h.write(A, 9 | FF, 7, 0, true);
        h.write(A, 11 | FF, 19, 0, true);
        h.credit(A, 10, CAP - 2);
        uint256 beforeWord = h.blockWord(A, 9);
        h.credit(A, 10, 4);
        uint256 expected = (beforeWord & ~(uint256(type(uint32).max) << 32))
            | (uint256(0x80000000 | CAP) << 32);
        assertEq(h.blockWord(A, 9), expected);
        assertEq(h.total(A, 10), CAP);
        h.credit(A, 10, type(uint32).max);
        assertEq(h.blockWord(A, 9), expected, "add widens before clamping");
        assertEq(h.length(10), 1);
        assertEq(h.legacy(A, 10), 0);
    }

    function test_RangeAndScaledAddsSaturate() public {
        h.range(A, 6, 5, 2, CAP - 1);
        h.range(A, 6, 5, 2, type(uint32).max);
        for (uint24 lvl = 6; lvl <= 14; lvl += 2) {
            assertEq(h.total(A, lvl), CAP);
            assertEq(h.length(lvl), 1);
            assertEq(h.legacy(A, lvl), 0);
        }
        h.credit(A, 9, CAP - 1);
        h.creditScaled(A, 9, 400);
        assertEq(h.total(A, 9), CAP);
    }

    function testFuzz_AddSaturatesBeforeNarrowing(uint32 initial, uint32 added, uint8 lane) public {
        lane %= 8;
        h.range(A, 9, 8, 1, 4);
        uint24 lvl = 9 + uint24(lane);
        uint32 start = initial > CAP ? CAP : initial;
        h.write(A, lvl | FF, start, 0, true);
        uint256 beforeWord = h.blockWord(A, 9);
        h.credit(A, lvl, added);
        uint256 sum = uint256(start) + added;
        uint256 mask = uint256(type(uint32).max) << (32 * lane);
        assertEq(h.total(A, lvl), sum > CAP ? CAP : sum);
        assertEq(h.blockWord(A, 9) & ~mask, beforeWord & ~mask);
        assertEq(h.length(lvl), 1);
        assertEq(h.legacy(A, lvl), 0);
    }

    function test_LogicalLevelsDoNotRecycleAt128() public {
        h.write(A, 7 | FF, 4, 0, false);
        h.write(A, 8 | FF, 8, 0, false);
        h.write(A, 135 | FF, 12, 0, false);
        assertEq(uint32(h.read(A, 7 | FF) >> 8), 4);
        assertEq(uint32(h.read(A, 8 | FF) >> 8), 8);
        assertEq(uint32(h.read(A, 135 | FF) >> 8), 12);
    }

    function test_FutureCycleReuseRequiresDrainAndHidesOldBalance() public {
        h.credit(A, 3, 4);
        h.credit(A, 4, 8);
        uint256 beforeWord = h.blockWord(A, 3);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        h.credit(A, 103, 12);
        assertEq(h.blockWord(A, 3), beforeWord);
        h.consume(3 | FF);
        h.credit(A, 103, 12);
        assertEq(h.total(A, 3), 0);
        assertEq(h.total(A, 103), 12);
        assertEq(h.total(A, 4), 8);
        assertEq(h.length(3), 0);
        assertEq(h.length(103), 1);
        h.consume(103 | FF);
        h.credit(A, 203, 20);
        assertEq(h.total(A, 103), 0);
        assertEq(h.total(A, 203), 20);
        assertEq(h.total(A, 0), 0);
    }

    function test_NearCurrentAndNextReuseOnlyAfterBothCohortsClear() public {
        h.write(A, 3, 11, 21, false);
        h.write(A, 3 | SLOT, 12, 22, true);
        h.write(A, 4, 13, 23, true);
        h.write(A, 4 | SLOT, 14, 24, false);
        uint256 beforeWord = h.legacy(A, 3);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        h.write(A, 5, 15, 25, false);
        assertEq(h.legacy(A, 3), beforeWord);
        h.write(A, 3, 0, 0, false);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        h.write(A, 5, 15, 25, false);
        h.write(A, 3 | SLOT, 0, 0, false);
        h.write(A, 5, 15, 25, false);
        h.write(A, 3, 0, 0, false);
        assertEq(h.total(A, 3), 0);
        assertEq(h.total(A, 4), 27);
        assertEq(h.total(A, 5), 15);
        assertEq(uint8(h.read(A, 4)), 23);
        assertEq(uint8(h.read(A, 4 | SLOT)), 24);
        assertEq(uint8(h.read(A, 5)), 25);
        assertEq(h.legacy(A, 3), h.legacy(A, 4));
    }

    function test_NearParityReusePreservesNextLevelAndFutureCycle() public {
        h.setLevel(2);
        h.credit(A, 3, 4);
        h.credit(A, 103, 12);
        h.setLevel(3);
        h.credit(A, 4, 8);
        h.consume(3);
        h.setLevel(4);
        h.credit(A, 5, 16);
        assertEq(h.total(A, 3), 0);
        assertEq(h.total(A, 4), 8);
        assertEq(h.total(A, 5), 16);
        assertEq(h.total(A, 103), 12);
    }

    function test_LockAllowsTopupAndRejectsNewRegistration() public {
        h.credit(A, 8, 4);
        h.lock();
        h.credit(A, 8, 4);
        assertEq(h.total(A, 8), 8);
        assertEq(h.length(8), 1);
        vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
        h.credit(B, 8, 4);
        vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
        h.credit(A, 9, 4);
        vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
        h.range(A, 8, 2, 1, 4);
        assertEq(h.total(A, 8), 8);
        assertEq(h.total(A, 9), 0);
    }

    function test_StridedRangesCrossWordBoundaries() public {
        h.range(A, 6, 25, 4, 4);
        for (uint24 lvl = 2; lvl <= 105; ++lvl) {
            bool expected = lvl >= 6 && lvl <= 102 && (lvl - 6) % 4 == 0;
            assertEq(h.total(A, lvl), expected ? 4 : 0);
            assertEq(h.length(lvl), expected ? 1 : 0);
        }
    }
}
