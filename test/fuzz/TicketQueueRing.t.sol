// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {TicketLevelPrep} from "../helpers/TicketLevelPrep.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract TicketQueueRingHarness is TicketLevelPrep, WalletSeed {
    function setLevel(uint24 lvl) external { level = lvl; jackpotPhaseFlag = false; }
    function enqueue(address player, uint24 lvl, uint32 n) external { _queueEntries(_seedWallet(player), lvl, n, false); }
    function append(uint24 key, uint32 pos) external { _tqAppend(key, pos); }
    function release(uint24 key) external { _releaseTicketQueue(key); }
    function writeKey(uint24 lvl) external view returns (uint24) { return _tqWriteKey(lvl); }
    function farKey(uint24 lvl) external pure returns (uint24) { return _tqFarFutureKey(lvl); }
    function physical(uint24 key) external pure returns (uint24) { return _ticketQueueStorageKey(key); }
    function count(uint24 key) external view returns (uint256) { return _ticketQueueLength(key); }
    function owed(uint24 key, address player) external view returns (uint80) { return _owedOf(key, player); }
    function position(uint24 key, address player) external view returns (uint32) { return _walletIdOf(player); }
    function prepare(uint24 lvl) external returns (bool) { return _prepareTicketLevel(lvl); }
    function flip() external { ticketWriteSlot = !ticketWriteSlot; }
    function reveal(uint24 key, uint8 trait) external {
        uint24 lvl = key & 0x3fffff;
        require(_prepareTicketLevel(lvl), "blocked");
        uint256[] storage q = ticketQueue[_ticketQueueStorageKey(key)];
        uint256 n = _ticketQueueLength(key);
        for (uint256 i; i < n; ++i) {
            uint32 pos = _tqPositionAt(q, i);
            uint80 packed = uint80(_entryRecordOf(key, pos) >> 160);
            _bucketAppendRun(_traitBufferBase(lvl), trait, pos - 1, uint32(packed >> 8), lvl);
            _setEntryOwed(key, pos, 0);
        }
        _releaseTicketQueue(key);
    }
    function bucketOwner(uint24 lvl, uint8 trait, uint256 i) external view returns (address) {
        require(i < _bucketLength(lvl, trait), "outside");
        return _bucketOwnerAt(lvl, trait, i);
    }
    function extsload(bytes32 slot) external view returns (bytes32 value) {
        assembly ("memory-safe") { value := sload(slot) }
    }
}

contract TicketQueueRingTest is Test {
    TicketQueueRingHarness h;
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);
    uint24 constant SLOT = 1 << 23;
    uint24 constant FAR = 1 << 22;
    function setUp() public { h = new TicketQueueRingHarness(); }

    function testFuzz_PhysicalKeysPreserveAbsoluteDomains(uint24 lvl, uint8 domain) public view {
        lvl &= 0x3fffff;
        uint24 flags = domain % 3 == 0 ? 0 : (domain % 3 == 1 ? SLOT : FAR);
        uint24 slot = lvl == 0 ? 0 : (lvl - 1) % (flags == FAR ? 100 : 2) + 1;
        assertEq(h.physical(lvl | flags), slot | flags);
    }

    function test_AbsoluteLevelSurvivesThreeCenturiesAndRootsStayBounded() public {
        for (uint24 lvl = 1; lvl <= 301; ++lvl) {
            h.setLevel(lvl - 1);
            h.enqueue(ALICE, lvl, 4);
            uint24 key = h.writeKey(lvl);
            assertEq(h.physical(key), (lvl - 1) % 2 + 1);
            assertEq(h.count(key), 1);
            h.reveal(key, 7);
            assertEq(h.bucketOwner(lvl, 7, 0), ALICE);
            assertEq(h.count(key), 0);
            assertEq(h.level(), lvl - 1);
        }
    }

    function test_CurrentAndPlus100CoexistAndGeneratedOwnersSurvive() public {
        h.enqueue(ALICE, 1, 4);
        h.reveal(1, 7);
        h.setLevel(1);
        h.enqueue(BOB, 101, 12);
        assertEq(h.physical(101 | FAR), 1 | FAR);
        assertEq(h.bucketOwner(1, 7, 0), ALICE);
        assertEq(uint32(h.owed(101 | FAR, BOB) >> 8), 12);
        assertEq(h.count(1 | FAR), 0, "future alias is not an old pending queue");
        h.setLevel(2);
        assertTrue(h.prepare(3), "future queue cannot block old generated buffer retirement");
        assertEq(h.count(101 | FAR), 1);
    }

    function test_NonemptyCollisionRevertsAndStaleReleaseCannotEraseFuture() public {
        h.setLevel(1);
        h.enqueue(ALICE, 101, 4);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        h.append(201 | FAR, 1);
        assertEq(h.count(101 | FAR), 1);
        h.release(1 | FAR);
        assertEq(h.count(101 | FAR), 1);
        assertEq(uint32(h.owed(101 | FAR, ALICE) >> 8), 4);
    }

    function test_ReusedQueueKeysKeepWalletBalancesSeparate() public {
        h.enqueue(ALICE, 1, 4);
        h.reveal(1, 7);
        h.setLevel(101);
        assertTrue(h.prepare(103));
        h.enqueue(BOB, 201, 20);
        assertEq(h.owed(1, ALICE), 0, "drained queue stays empty after physical root reuse");
        assertEq(h.owed(201 | FAR, ALICE), 0);
        assertEq(uint32(h.owed(201 | FAR, BOB) >> 8), 20);
        h.enqueue(ALICE, 201, 8);
        assertEq(uint32(h.owed(201 | FAR, ALICE) >> 8), 8);
        assertEq(uint32(h.owed(201 | FAR, BOB) >> 8), 20);
    }

    function test_BothNearCohortsRetainIndependentOwedAndReuse() public {
        h.enqueue(ALICE, 1, 4);
        h.flip();
        h.enqueue(ALICE, 1, 8);
        assertEq(h.count(1), 1);
        assertEq(h.count(1 | SLOT), 1);
        assertEq(uint32(h.owed(1, ALICE) >> 8), 4);
        assertEq(uint32(h.owed(1 | SLOT, ALICE) >> 8), 8);
        h.reveal(1, 7);
        h.reveal(1 | SLOT, 7);
        assertEq(h.bucketOwner(1, 7, 11), ALICE);
        h.setLevel(100);
        h.enqueue(BOB, 101, 4);
        assertEq(h.count(1 | SLOT), 0);
        assertEq(h.count(101 | SLOT), 1);
        assertEq(h.owed(101 | SLOT, ALICE), 0);
    }

    function test_LensAuthenticatesAbsoluteLevelBeforeReadingReusedQueue() public {
        DegenerusGameLens lens = new DegenerusGameLens();
        h.setLevel(1);
        h.enqueue(BOB, 101, 4);
        uint32 pos = h.position(101 | FAR, BOB);
        (bool found, uint32 index,, uint32 total) = lens.findQueueEntry(address(h), 101 | FAR, pos, 0, 1);
        assertTrue(found); assertEq(index, 0); assertEq(total, 1);
        (found,,,total) = lens.findQueueEntry(address(h), 1 | FAR, pos, 0, 1);
        assertFalse(found); assertEq(total, 0);
    }
}
