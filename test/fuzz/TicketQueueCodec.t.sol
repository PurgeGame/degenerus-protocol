// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

contract TicketQueueCodecHarness is DegenerusGameStorage, WalletSeed {
    function roots() external pure returns (uint256 q, uint256 locator, uint256 owners, uint256 pending) {
        assembly { q := ticketQueue.slot locator := mintPacked_.slot owners := wallets.slot pending := ticketPending.slot }
    }
    function writeOwed(uint24 lvl, uint32 pos, uint80 packed) external { _setEntryOwed(lvl, pos, packed); }
    function record(uint24 lvl, uint32 pos) external view returns (uint256) { return _entryRecordOf(lvl, pos); }
    function seedBucket(uint24 lvl, uint32 pos) external {
        _setTicketBufferLevel(lvl);
        _bucketAppendRun(_traitBufferBase(lvl), 17, uint256(pos), 1, lvl);
    }
    function bucketOwner(uint24 lvl) external view returns (address) { return _bucketOwnerAt(lvl, 17, 0); }
    function append(uint24 key, uint32 pos) external { _tqAppend(key, pos); }
    function appendLanes(uint24 key, uint256 lanes, uint256 count) external { _tqAppendLanes(key, lanes, count); }
    function position(uint24 key, uint256 k) external view returns (uint32) {
        require(k < _ticketQueueLength(key));
        return _tqPositionAt(ticketQueue[_ticketQueueStorageKey(key)], k);
    }
    function owner(uint24 key, uint24 lvl, uint256 k) external view returns (address) {
        require(k < _ticketQueueLength(key));
        return _walletKey(_tqPositionAt(ticketQueue[_ticketQueueStorageKey(key)], k));
    }
    function length(uint24 key) external view returns (uint256) { return _ticketQueueLength(key); }
    function remove(uint24 key, uint256 k) external {
        require(k < _ticketQueueLength(key));
        _tqSwapPop(ticketQueue[_ticketQueueStorageKey(key)], k);
    }
    function release(uint24 key) external { _releaseTicketQueue(key); }
    function word(uint24 key, uint256 w) external view returns (uint256 value) {
        uint256[] storage q = ticketQueue[_ticketQueueStorageKey(key)];
        assembly ("memory-safe") {
            mstore(0, q.slot)
            value := sload(add(keccak256(0, 32), w))
        }
    }
    function seedWord(uint24 key, uint256 value) external {
        (uint256[] storage q, uint256 header) = _bindTicketQueue(key);
        assembly ("memory-safe") {
            sstore(q.slot, or(and(header, not(0xffffffff)), 8))
            mstore(0, q.slot)
            sstore(keccak256(0, 32), value)
        }
    }
    function seedOwner(uint24 lvl, uint32 pos, address player) external {
        require(pos != 0);
        walletIds[player] = pos;
        uint256[] storage table = wallets;
        assembly ("memory-safe") {
            if iszero(gt(sload(table.slot), pos)) { sstore(table.slot, add(pos, 1)) }
            mstore(0, table.slot)
            sstore(add(keccak256(0, 32), pos), player)
        }
    }
}

contract TicketQueueCodecTest is Test {
    TicketQueueCodecHarness h;
    function setUp() public { h = new TicketQueueCodecHarness(); }

    function testFuzz_BulkAppendPreservesLivePrefixAndClearsStaleTail(uint8 fillSeed, uint8 countSeed) public {
        uint256 fill = bound(fillSeed, 0, 15);
        uint256 count = bound(countSeed, 1, 8);
        // Leave stale all-ones words behind the logical end, including spillover.
        h.seedWord(77, type(uint256).max);
        h.release(77);
        for (uint256 i; i < fill; ++i) h.append(77, uint32(100 + i));
        uint256 lanes;
        for (uint256 i; i < count; ++i) lanes |= uint256(200 + i) << (32 * i);
        h.appendLanes(77, lanes, count);
        assertEq(h.length(77), fill + count);
        for (uint256 i; i < fill; ++i) assertEq(h.position(77, i), 100 + i);
        for (uint256 i; i < count; ++i) assertEq(h.position(77, fill + i), 200 + i);
        h.append(77, 999);
        assertEq(h.position(77, fill + count), 999);
    }

    function test_ReferenceModelRootsMatchCompilerLayout() public view {
        (uint256 q, uint256 locator, uint256 owners, uint256 pending) = h.roots();
        // GameSlots is pinned to the compiled layout by StorageSlotPins.
        assertEq(q, GameSlots.TICKET_QUEUE); assertEq(locator, GameSlots.MINT_PACKED);
        assertEq(owners, GameSlots.WALLETS); assertEq(pending, GameSlots.TICKET_PENDING);
    }

    function testFuzz_OwedRewritePreservesOwnerAndNeighbour(address player, uint80 owed, uint32 position) public {
        position = uint32(bound(position, 1, uint256(type(uint32).max) - 1));
        h.seedOwner(7, position, player);
        h.seedOwner(7, position + 1, address(0xBEEF));
        h.seedBucket(7, position);
        h.writeOwed(7, position, owed);
        assertEq(h.bucketOwner(7), player, "trait decoder must mask the mutable owed field");
        uint80 expected = owed == 0 ? 0 : (uint80(position) << 48) | (owed & ((uint80(1) << 41) - 1));
        assertEq(h.record(7, position), uint256(uint160(player)) | (uint256(expected) << 160));
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
        assertEq(h.owner(5, 5, 0), address(0), "empty lane does not alias the first account");
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
