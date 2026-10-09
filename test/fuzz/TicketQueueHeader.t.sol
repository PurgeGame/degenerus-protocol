// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

/// @dev Production ticket-queue helpers over bare Game storage.
contract TicketQueueHeaderHarness is DegenerusGameStorage, WalletSeed {
    function seedWallet(address owner) external returns (uint32) { return _seedWallet(owner); }
    function append(uint24 key, uint32 id) external { _tqAppend(key, id); }
    function appendLanes(uint24 key, uint256 lanes, uint256 count) external { _tqAppendLanes(key, lanes, count); }
    function release(uint24 key) external { _releaseTicketQueue(key); }
    function length(uint24 key) external view returns (uint256) { return _ticketQueueLength(key); }
    function at(uint24 key, uint256 k) external view returns (uint32) {
        return _tqPositionAt(ticketQueue[_ticketQueueStorageKey(key)], k);
    }
    function physical(uint24 key) external pure returns (uint24) { return _ticketQueueStorageKey(key); }
    function headerSlot(uint24 physicalKey) public pure returns (bytes32 slot) {
        assembly ("memory-safe") {
            mstore(0, physicalKey)
            mstore(32, ticketQueue.slot)
            slot := keccak256(0, 64)
        }
    }
    function header(uint24 physicalKey) external view returns (uint256 h) {
        bytes32 slot = headerSlot(physicalKey);
        assembly ("memory-safe") { h := sload(slot) }
    }
    function setHeader(uint24 physicalKey, uint256 h) external {
        bytes32 slot = headerSlot(physicalKey);
        assembly ("memory-safe") { sstore(slot, h) }
    }
    function setFarOwed(uint24 lvl, uint32 id, uint32 owed) external {
        _setEntryOwed(lvl | TICKET_FAR_FUTURE_BIT, id, (uint80(id) << OWNER_IDX_SHIFT) | (uint80(owed) << 8));
    }
    function farLane(uint24 lvl, uint32 id) external view returns (uint256) { return _farFutureLane(lvl, id); }
}

/// @notice Phase B: the queue length word carries the occupying level tag.
contract TicketQueueHeaderTest is Test {
    TicketQueueHeaderHarness h;
    uint24 constant FF = uint24(1) << 22;
    uint32 a;
    uint32 b;

    function setUp() public {
        h = new TicketQueueHeaderHarness();
        a = h.seedWallet(address(0xA11CE));
        b = h.seedWallet(address(0xB0B));
    }

    function test_AppendWritesCountAndExplicitTagInOneWord() public {
        uint24 key = FF | 7;
        h.append(key, a);
        h.append(key, b);
        assertEq(h.header(h.physical(key)), 2 | (uint256(7) << 32));
        assertEq(h.length(key), 2);
        assertEq(h.at(key, 0), a);
        assertEq(h.at(key, 1), b);
    }

    function test_GenesisRootMaterializesItsImplicitTag() public {
        // Physical root FF|5 implicitly belongs to level 5 while its header is zero.
        uint24 key = FF | 5;
        assertEq(h.header(h.physical(key)), 0);
        h.append(key, a);
        assertEq(h.header(h.physical(key)), 1 | (uint256(5) << 32), "first append writes the tag");
        h.release(key);
        assertEq(h.header(h.physical(key)), uint256(5) << 32, "release keeps a nonzero header");
        assertEq(h.length(key), 0);
    }

    function test_NonzeroTagWithZeroCountIsEmptyAndReusable() public {
        uint24 key = FF | 9;
        h.append(key, a);
        h.release(key);
        assertEq(h.length(key), 0, "tag alone is empty");
        h.append(key, b);
        assertEq(h.length(key), 1);
        assertEq(h.at(key, 0), b, "append restarts at lane zero");
        assertEq(h.header(h.physical(key)), 1 | (uint256(9) << 32));
    }

    function test_LaterLevelRebindsAnEmptyRootAndOldLevelReadsEmpty() public {
        uint24 oldKey = FF | 12;
        uint24 newKey = FF | 112; // same physical root, one century later
        assertEq(h.physical(oldKey), h.physical(newKey));
        h.append(oldKey, a);
        h.release(oldKey);
        h.append(newKey, b);
        assertEq(h.header(h.physical(newKey)), 1 | (uint256(112) << 32));
        assertEq(h.length(oldKey), 0, "a reused root never reports the old level");
        assertEq(h.length(newKey), 1);
    }

    function test_LiveCollisionReverts() public {
        h.append(FF | 12, a);
        vm.expectRevert(bytes4(keccak256("E()")));
        h.append(FF | 112, b);
        assertEq(h.length(FF | 12), 1);
    }

    function test_StaleReleaseLeavesNewOccupantIntact() public {
        h.append(FF | 12, a);
        h.release(FF | 12);
        h.append(FF | 112, b);
        h.release(FF | 12);
        assertEq(h.length(FF | 112), 1);
        assertEq(h.header(h.physical(FF | 112)), 1 | (uint256(112) << 32));
    }

    function test_PackedLaneAppendPreservesTag() public {
        uint24 key = FF | 40;
        h.appendLanes(key, uint256(a) | (uint256(b) << 32), 2);
        assertEq(h.header(h.physical(key)), 2 | (uint256(40) << 32));
        h.appendLanes(key, uint256(b), 1);
        assertEq(h.length(key), 3);
        assertEq(h.at(key, 2), b);
    }

    function testFuzz_CountMaskedAtBounds(uint32 count, uint24 lvl) public {
        lvl = uint24(bound(lvl, 1, 0x3fffff));
        uint24 key = FF | lvl;
        uint24 root = h.physical(key);
        h.setHeader(root, uint256(count) | (uint256(lvl) << 32));
        assertEq(h.length(key), count, "count reads back exactly");
        uint24 other = lvl > 100 ? lvl - 100 : lvl + 100;
        assertEq(h.length(FF | other), 0, "another level on the root reads empty");
    }

    function test_FarFutureLaneAuthenticatesAgainstHeaderTag() public {
        h.setFarOwed(15, a, 4);
        assertGt(h.farLane(15, a), 0, "implicit tag authenticates the genesis level");
        // Level 115 occupies the root: level 15's owed lane no longer authenticates.
        h.setHeader(h.physical(FF | 115), uint256(115) << 32);
        assertEq(h.farLane(15, a), 0);
        h.setHeader(h.physical(FF | 115), uint256(15) << 32);
        assertGt(h.farLane(15, a), 0, "explicit matching tag authenticates");
    }
}
