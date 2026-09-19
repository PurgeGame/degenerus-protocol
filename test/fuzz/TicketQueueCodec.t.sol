// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

contract TicketQueueCodecHarness is DegenerusGameStorage {
    function roots() external pure returns (uint256 q, uint256 locator, uint256 owners) {
        assembly { q := ticketQueue.slot locator := entryOwnerPosition.slot owners := lvlEntryOwner.slot }
    }
    function writeOwed(uint24 lvl, uint32 pos, uint80 packed) external { _setEntryOwed(lvl, pos, packed); }
    function record(uint24 lvl, uint32 pos) external view returns (uint256) { return _entryRecord(lvl, pos); }
    function seedBucket(uint24 lvl, uint32 pos) external {
        _bucketAppendRun(uint256(keccak256(abi.encode(lvl, uint256(8)))), 17, uint256(pos) - 1, 1);
    }
    function bucketOwner(uint24 lvl) external view returns (address) { return _bucketOwnerAt(lvl, 17, 0); }
    function append(uint24 key, uint32 pos) external { _tqAppend(key, pos); }
    function position(uint24 key, uint256 k) external view returns (uint32) {
        require(k < ticketQueue[key].length);
        return _tqPositionAt(ticketQueue[key], k);
    }
    function owner(uint24 key, uint24 lvl, uint256 k) external view returns (address) {
        require(k < ticketQueue[key].length);
        return _tqOwnerAt(ticketQueue[key], lvl, k);
    }
    function length(uint24 key) external view returns (uint256) { return ticketQueue[key].length; }
    function remove(uint24 key, uint256 k) external {
        require(k < ticketQueue[key].length);
        _tqSwapPop(ticketQueue[key], k);
    }
    function release(uint24 key) external { _releaseTicketQueue(key); }
    function word(uint24 key, uint256 w) external view returns (uint256 value) {
        uint256[] storage q = ticketQueue[key];
        assembly ("memory-safe") {
            mstore(0, q.slot)
            value := sload(add(keccak256(0, 32), w))
        }
    }
    function seedWord(uint24 key, uint256 value) external {
        uint256[] storage q = ticketQueue[key];
        assembly ("memory-safe") {
            sstore(q.slot, 8)
            mstore(0, q.slot)
            sstore(keccak256(0, 32), value)
        }
    }
    function seedOwner(uint24 lvl, uint32 pos, address player) external {
        require(pos != 0);
        EntryOwner[] storage owners = lvlEntryOwner[lvl];
        assembly ("memory-safe") {
            mstore(0, owners.slot)
            sstore(add(keccak256(0, 32), sub(pos, 1)), player)
        }
    }
}

contract TicketQueueCodecTest is Test {
    TicketQueueCodecHarness h;
    function setUp() public { h = new TicketQueueCodecHarness(); }

    function test_ReferenceModelRootsMatchCompilerLayout() public view {
        (uint256 q, uint256 locator, uint256 owners) = h.roots();
        assertEq(q, 12); assertEq(locator, 13); assertEq(owners, 67);
    }

    function testFuzz_OwedRewritePreservesOwnerAndNeighbour(address player, uint80 owed, uint32 position) public {
        position = uint32(bound(position, 1, uint256(type(uint32).max) - 1));
        h.seedOwner(7, position, player);
        h.seedOwner(7, position + 1, address(0xBEEF));
        h.seedBucket(7, position);
        h.writeOwed(7, position, owed);
        assertEq(h.bucketOwner(7), player, "trait decoder must mask the mutable owed field");
        assertEq(h.record(7, position), uint256(uint160(player)) | (uint256(owed) << 160));
        assertEq(h.record(7, position + 1), uint160(address(0xBEEF)));
        h.append(7, position);
        assertEq(h.owner(7, 7, 0), player);
        h.writeOwed(7, position, 0);
        assertEq(h.record(7, position), uint160(player));
        assertEq(h.bucketOwner(7), player);
        assertEq(h.owner(7, 7, 0), player, "draining preserves historical bucket owners");
    }

    function testFuzz_EncodeDecodedWordEqualsOriginal(uint256 word, uint24 key) public {
        h.seedWord(key, word);
        uint256 encoded;
        for (uint256 i; i < 8; ++i) encoded |= uint256(h.position(key, i)) << (32 * i);
        assertEq(encoded, word, "every bit of all eight lanes must round-trip");
    }

    function testFuzz_DecodeAppendedPositionsEqualsOriginal(uint32[8] memory positions, uint24 key) public {
        uint256 encoded;
        for (uint256 i; i < 8; ++i) {
            if (positions[i] == 0) positions[i] = 1;
            h.append(key, positions[i]);
            encoded |= uint256(positions[i]) << (32 * i);
        }
        assertEq(h.word(key, 0), encoded);
        for (uint256 i; i < 8; ++i) assertEq(h.position(key, i), positions[i]);
    }

    function test_RegistryIndicesAboveUint24DoNotAlias() public {
        uint32[4] memory pos = [uint32(1), uint32(0x01000001), uint32(0x80000001), type(uint32).max - 1];
        for (uint256 i; i < pos.length; ++i) {
            h.seedOwner(123, pos[i], address(uint160(100 + i)));
            h.append(123 | uint24(1 << 23), pos[i]);
        }
        for (uint256 i; i < pos.length; ++i) {
            assertEq(h.owner(123 | uint24(1 << 23), 123, i), address(uint160(100 + i)));
        }
    }

    function test_ZeroLaneCannotResolveFirstOwner() public {
        h.seedOwner(5, 1, address(0xBEEF));
        h.seedWord(5, 0);
        vm.expectRevert(bytes4(keccak256("E()")));
        h.owner(5, 5, 0);
        vm.expectRevert(bytes4(keccak256("E()")));
        h.append(5, 0);
        h.release(5);
        h.append(5, 1);
        assertEq(h.owner(5, 5, 0), address(0xBEEF), "registry index zero is encoded as one");
    }

    function testFuzz_SwapPopPreservesEveryNeighbour(uint8 lengthSeed, uint8 indexSeed, uint32 salt) public {
        uint256 n = bound(lengthSeed, 1, 40);
        uint256 index = uint256(indexSeed) % n;
        uint32[] memory expected = new uint32[](n);
        for (uint256 i; i < n; ++i) {
            expected[i] = uint32(uint256(keccak256(abi.encode(salt, i))));
            if (expected[i] == 0) expected[i] = 1;
            h.append(5, expected[i]);
        }
        h.remove(5, index);
        expected[index] = expected[n - 1];
        assertEq(h.length(5), n - 1);
        for (uint256 i; i < n - 1; ++i) assertEq(h.position(5, i), expected[i]);
        assertEq(uint32(h.word(5, (n - 1) / 8) >> (((n - 1) % 8) * 32)), 0);
        h.append(5, type(uint32).max - 1);
        assertEq(h.position(5, n - 1), type(uint32).max - 1);
        for (uint256 i; i < n - 1; ++i) assertEq(h.position(5, i), expected[i]);
    }

    function test_ReleaseAndReuseOverwritesStaleWords() public {
        for (uint256 i; i < 25; ++i) h.append(5, type(uint32).max - 1);
        h.release(5);
        assertEq(h.length(5), 0);
        for (uint32 i = 1; i <= 25; ++i) {
            h.append(5, i);
            for (uint256 j; j < i; ++j) assertEq(h.position(5, j), j + 1);
        }
        assertEq(h.word(5, 3), 25, "fresh tail clears stale upper lanes");
    }
}
