// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {TicketLevelPrep} from "../helpers/TicketLevelPrep.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract TicketRecyclingHarness is TicketLevelPrep, WalletSeed {
    function completed(uint24 lvl) external { level = lvl; jackpotPhaseFlag = false; }
    function prepare(uint24 lvl) external returns (bool) { return _prepareTicketLevel(lvl); }
    function append(uint24 lvl, uint8 trait, address owner, uint256 n) external {
        require(_ticketBufferLevel(lvl) == lvl, "unprepared");
        uint256 idx = uint256(_seedWallet(owner));
        _bucketAppendRun(_traitBufferBase(lvl), trait, idx, n, lvl);
    }
    function count(uint24 lvl, uint8 trait) external view returns (uint256) { return _bucketLength(lvl, trait); }
    function ownerAt(uint24 lvl, uint8 trait, uint256 i) external view returns (address) {
        require(i < _bucketLength(lvl, trait));
        return _bucketOwnerAt(lvl, trait, i);
    }
    function retired(uint24 lvl) external view returns (bool) { return _ticketLevelRetired(lvl); }
    function pending(uint24 lvl, bool write, uint256 n) external {
        (uint256[] storage q, uint256 header) = _bindTicketQueue(write ? _tqWriteKey(lvl) : _tqReadKey(lvl));
        assembly ("memory-safe") { sstore(q.slot, or(and(header, not(0xffffffff)), n)) }
    }
    function farPending(uint24 lvl, uint256 n) external {
        (uint256[] storage q, uint256 header) = _bindTicketQueue(_tqFarFutureKey(lvl));
        assembly ("memory-safe") { sstore(q.slot, or(and(header, not(0xffffffff)), n)) }
    }
    function seated(uint24 lvl, uint32 n) external { ticketLevel=lvl; ticketSeats=n; }
    function livePhase(uint24 lvl) external { level=lvl; jackpotPhaseFlag=true; }
    function foilPending(uint24, uint256 n) external {
        foilReadCount = uint32(n);
        foilCursor = 0;
    }
    function latchTerminal(uint24 payoutLevel) external {
        level = payoutLevel - 1;
        _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, 2);
    }
    function seedHuge(uint24 lvl, uint8 trait, uint256 n) external {
        lvlTraitEntry[lvl & 1][trait] = n;
        traitBucketLive[lvl & 1] |= uint256(1) << trait;
    }
}

contract TicketStorageRecyclingTest is Test {
    TicketRecyclingHarness h;
    function setUp() public { h = new TicketRecyclingHarness(); }

    function test_RetainedUntilActualTakeoverAndOtherParitySurvives() public {
        assertTrue(h.prepare(1));
        h.append(1, 7, address(10), 9);
        assertTrue(h.prepare(2));
        h.append(2, 7, address(20), 7);
        h.completed(2);
        assertFalse(h.retired(1));
        assertEq(h.count(1, 7), 9);
        assertTrue(h.prepare(3));
        assertTrue(h.retired(1));
        assertEq(h.count(3, 7), 0);
        assertEq(h.count(2, 7), 7);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        h.count(1, 7);
        assertFalse(h.prepare(1));
    }

    function test_BothQueueHalvesAndFoilBlockRetirementWithoutLosingWork() public {
        assertTrue(h.prepare(1));
        h.append(1, 7, address(10), 1);
        h.completed(2);
        h.pending(1, true, 1);
        assertFalse(h.prepare(3));
        assertEq(h.count(1, 7), 1);
        h.pending(1, true, 0);
        h.pending(1, false, 1);
        assertFalse(h.prepare(3));
        h.pending(1, false, 0);
        h.foilPending(1, 1);
        assertFalse(h.prepare(3));
        h.foilPending(1, 0);
        assertTrue(h.prepare(3));
    }

    function testFuzz_ShrinkAndRegrowNeverMixOwners(uint8 a, uint8 b) public {
        uint256 oldCount = uint256(a) + 9;
        uint256 newCount = uint256(b) + 1;
        assertTrue(h.prepare(1));
        h.append(1, 7, address(10), oldCount);
        h.append(1, 7, address(11), oldCount);
        h.completed(2);
        assertTrue(h.prepare(3));
        h.append(3, 7, address(30), newCount);
        h.append(3, 7, address(31), 9);
        assertEq(h.count(3, 7), newCount + 9);
        for (uint256 i; i < newCount + 9; ++i) {
            assertEq(h.ownerAt(3, 7, i), i < newCount ? address(30) : address(31));
        }
    }

    function test_FutureSeatedAndActiveInventoryMustSurvive() public {
        assertTrue(h.prepare(1)); h.completed(2);
        h.farPending(1,1); assertFalse(h.prepare(3)); h.farPending(1,0);
        h.seated(1,1); assertFalse(h.prepare(3)); h.seated(1,0);
        h.livePhase(1); assertFalse(h.prepare(3));
        h.completed(0); assertFalse(h.prepare(3));
        h.completed(2); assertTrue(h.prepare(3));
    }
    function test_TerminalFreezeAllowsFirstPreparationOfPayoutLevelOnly() public {
        assertTrue(h.prepare(1));
        h.append(1, 7, address(10), 1);
        h.latchTerminal(3);
        assertTrue(h.prepare(3), "paid terminal tickets can materialize into a new buffer");
        h.append(3, 7, address(30), 1);
        assertEq(h.ownerAt(3, 7, 0), address(30));
        assertFalse(h.prepare(4), "unrelated level cannot acquire a frozen terminal buffer");
    }

    function test_ResetTouchesNoPayloadAtMillionOccurrences() public {
        assertTrue(h.prepare(1));
        h.completed(2);
        h.seedHuge(1, 7, 1_000_000);
        h.seedHuge(1, 8, 1_000_000);
        vm.record();
        assertTrue(h.prepare(3));
        (, bytes32[] memory writes) = vm.accesses(address(h));
        assertEq(writes.length, 2, "only the fixed parity stamp and bitmap are written");
        assertEq(h.count(3, 7), 0);
    }
}
