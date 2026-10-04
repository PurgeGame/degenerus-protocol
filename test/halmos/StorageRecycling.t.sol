// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

contract RecyclingSymbolicHarness is DegenerusGameStorage {
    function header(uint24 lvl, uint32 count, uint224 tail) external {
        _setTicketBufferLevel(lvl);
        traitBucketLive[lvl & 1] |= uint256(1) << 7;
        uint256 mask = (uint256(1) << ((uint256(count) & 7) * 32)) - 1;
        lvlTraitEntry[lvl & 1][7] = uint256(count) | ((uint256(tail) & mask) << 32);
    }
    function count(uint24 lvl) external view returns (uint256) { return _bucketLengthUnchecked(lvl, 7); }
    function encoded(uint24 lvl) external view returns (uint256) { return lvlTraitEntry[lvl & 1][7]; }
    function append(uint24 lvl, uint32 owner) external returns (uint256 f, uint256 d) { return _bucketAppendRun(_traitBufferBase(lvl), 7, owner, 1, lvl); }
    function seedStale(uint256 payload) external {
        _setTicketBufferLevel(1);
        traitBucketLive[1] = uint256(1) << 7;
        lvlTraitEntry[1][7] = payload;
        uint256 elem = _traitBufferBase(1) + 7;
        assembly ("memory-safe") { mstore(0, elem) sstore(keccak256(0, 32), payload) }
        _setTicketBufferLevel(3);
    }
    function appendStaleRun(uint32 owner, uint8 n) external returns (uint256 f, uint256 d) { return _bucketAppendRun(_traitBufferBase(3), 7, owner, n, 3); }
    function appendStaleLanes(uint256 lanes, uint8 n) external returns (uint256 f, uint256 d) { return _bucketAppendLanes(_traitBufferBase(3), 7, lanes, n, 3); }
    function payload(uint24 lvl, uint256 k) external view returns (uint256) { return _bucketWordAtUnchecked(lvl, 7, k); }
    function rawData(uint24 lvl) external view returns (uint256 word) {
        uint256 elem = _traitBufferBase(lvl) + 7;
        assembly ("memory-safe") { mstore(0, elem) word := sload(keccak256(0, 32)) }
    }
    function bits(uint8 parity) external view returns (uint256) { return traitBucketLive[parity]; }
    function seedBits(uint256 even, uint256 odd) external { traitBucketLive[0] = even; traitBucketLive[1] = odd; }
    function invalidate(uint24 lvl) external { traitBucketLive[lvl & 1] &= ~(uint256(1) << 7); }
    function stamp(uint24 lvl) external { _setTicketBufferLevel(lvl); }
    function stamped(uint24 lvl) external view returns (uint24) { return _ticketBufferLevel(lvl); }
    function seedPacked5(uint256 word) external { assembly ("memory-safe") { sstore(ticketBufferLevels.slot, word) } }
    function packed5() external view returns (uint256 word) { assembly ("memory-safe") { word := sload(ticketBufferLevels.slot) } }
    function seedRng(uint16 flags, uint256 word, uint48 cursor, bool human) external {
        rngFlagsAndNudges = flags;
        rngWordCurrent = word;
        boxCursor = cursor;
        humanReadComplete = human;
    }
    function flags() external view returns (uint16) { return rngFlagsAndNudges; }
    function readBuffer() external view returns (uint48) { return _rngReadBuffer(); }
    function writeBuffer() external view returns (uint48) { return _rngWriteBuffer(); }
    function swap() external { _swapRngBuffers(); }
    function humanDone() external view returns (bool) { return humanReadComplete; }
    function cursor() external view returns (uint48) { return boxCursor; }
    function wordAt(uint48 buffer) external view returns (uint256) { return _lootboxWord(buffer); }
    function setNudges(uint16 count_) external { _setNudgeCount(count_); }
    function nudges() external view returns (uint256) { return _nudgeCount(); }
    function live(uint48 index) external view returns (bool) { return _lootboxBufferValid(index); }
}

/// @dev Header proofs replace the old per-trait stamp/partial-data-word proofs.
///      Supported additions are explicitly assumed below 2^32; production adds no overflow revert.
contract StorageRecyclingSymbolicTest is Test {
    RecyclingSymbolicHarness h;
    function setUp() public { h = new RecyclingSymbolicHarness(); }
    function _mask(uint256 n) internal pure returns (uint256) {
        return n == 8 ? type(uint256).max : (uint256(1) << (n * 32)) - 1;
    }
    function check_header_count_tail_roundtrip(uint24 lvl, uint32 count, uint224 tail) public {
        vm.assume(lvl > 0);
        h.header(lvl, count, tail);
        assertEq(h.count(lvl), count);
        assertEq(h.encoded(lvl), uint256(count) | ((uint256(tail) & _mask(count & 7)) << 32));
        assertEq(h.payload(lvl, uint256(count) & ~uint256(7)), uint256(tail) & _mask(count & 7));
    }
    function check_append_preserves_tail_and_completes_word(uint24 lvl, uint32 count, uint224 tail, uint32 owner) public {
        vm.assume(lvl > 0 && count < type(uint32).max);
        h.header(lvl, count, tail);
        h.append(lvl, owner);
        assertEq(h.count(lvl), uint256(count) + 1);
        uint256 expected = (uint256(tail) & _mask(count & 7)) | (uint256(owner) << ((uint256(count) & 7) * 32));
        assertEq(h.payload(lvl, uint256(count) & ~uint256(7)), expected);
        assertEq((h.encoded(lvl) >> 32) & ~_mask((uint256(count) + 1) & 7), 0);
    }
    function check_stale_run_initializes_header_tail(uint256 oldWord, uint32 owner, uint8 n) public {
        vm.assume(n > 0 && n <= 8);
        h.seedStale(oldWord);
        assertEq(h.count(3), 0);
        h.appendStaleRun(owner, n);
        uint256 full = uint256(owner) * 0x0000000100000001000000010000000100000001000000010000000100000001;
        assertEq(h.payload(3, 0), full & _mask(n));
        assertEq(h.count(3), n);
        assertEq(h.count(1), 0);
        assertEq(h.bits(1), uint256(1) << 7);
        if (n < 8) assertEq(h.rawData(3), oldWord, "partial append writes no data word");
        else assertEq(h.rawData(3), full, "complete word replaces stale data");
        assertEq(h.encoded(3) >> 32, n == 8 ? 0 : full & _mask(n));
    }
    function check_stale_lanes_initialize_header_tail(uint256 oldWord, uint256 lanes, uint8 n) public {
        vm.assume(n > 0 && n <= 8);
        uint256 valid = lanes & _mask(n);
        h.seedStale(oldWord);
        h.appendStaleLanes(valid, n);
        assertEq(h.payload(3, 0), valid);
        assertEq(h.count(3), n);
        assertEq(h.encoded(3) >> 32, n == 8 ? 0 : valid);
        if (n < 8) assertEq(h.rawData(3), oldWord);
        else assertEq(h.rawData(3), valid);
    }
    function check_live_tail_word_price(uint256 oldWord, uint224 tail, uint32 owner) public {
        h.seedStale(oldWord);
        h.header(3, 7, tail);
        (uint256 f, uint256 d) = h.append(3, owner);
        assertEq(f, oldWord == 0 ? 1 : 0, "tail completion prices its actual backing word");
        assertEq(f + d, 2, "one header and one completed word");
    }
    function check_stale_run_prices_original_slots(uint256 oldWord, uint32 owner, uint8 n) public {
        vm.assume(n > 0 && n <= 8);
        h.seedStale(oldWord);
        (uint256 f, uint256 d) = h.appendStaleRun(owner, n);
        uint256 fresh = 1 + (oldWord == 0 ? 1 : 0) + (n == 8 && oldWord == 0 ? 1 : 0);
        assertEq(f, fresh, "classify header before logical reset; bitmap and completed word priced too");
        assertEq(f + d, 2 + (n == 8 ? 1 : 0));
    }
    function check_stale_lanes_prices_original_slots(uint256 oldWord, uint256 lanes, uint8 n) public {
        vm.assume(n > 0 && n <= 8);
        h.seedStale(oldWord);
        (uint256 f, uint256 d) = h.appendStaleLanes(lanes & _mask(n), n);
        uint256 fresh = 1 + (oldWord == 0 ? 1 : 0) + (n == 8 && oldWord == 0 ? 1 : 0);
        assertEq(f, fresh);
        assertEq(f + d, 2 + (n == 8 ? 1 : 0));
    }
    function check_bitmap_reset_preserves_other_parity(uint256 even, uint256 odd, uint24 lvl) public {
        vm.assume(lvl > 0);
        h.seedBits(even, odd); h.stamp(lvl);
        assertEq(h.bits(uint8(lvl & 1)), 0);
        assertEq(h.bits(uint8((lvl & 1) ^ 1)), lvl & 1 == 0 ? odd : even);
    }
    function check_same_level_preserves_bitmap(uint256 even, uint256 odd, uint24 lvl) public {
        vm.assume(lvl > 0);
        h.stamp(lvl); h.seedBits(even, odd); h.stamp(lvl);
        assertEq(h.bits(0), even); assertEq(h.bits(1), odd);
    }
    function check_full_level_equality(uint24 lvl, uint32 count) public {
        vm.assume(lvl > 0 && lvl < type(uint24).max - 2);
        h.header(lvl, count, 0);
        assertEq(h.count(lvl + 2), 0, "unprepared future cannot read old valid bitmap");
        assertEq(h.count(lvl), count);
    }
    function check_unset_bitmap_hides_header(uint24 lvl, uint32 count) public {
        vm.assume(lvl > 0);
        h.header(lvl, count, 0); h.invalidate(lvl); assertEq(h.count(lvl), 0);
    }
    function check_stamp_half_and_neighbors_are_isolated(uint256 prior, uint24 lvl) public {
        h.seedPacked5(prior);
        uint256 shift = 80 + uint256(lvl & 1) * 24;
        uint256 mask = uint256(type(uint24).max) << shift;
        h.stamp(lvl);
        assertEq(h.packed5(), (prior & ~mask) | (uint256(lvl) << shift));
        assertEq(h.stamped(lvl), lvl);
        assertEq(h.stamped(lvl ^ 1), uint24(prior >> (80 + uint256((lvl ^ 1) & 1) * 24)));
    }
    function check_binary_tag_validation(uint48 index) public { assertEq(h.live(index), index < 2); }

    function check_binary_swap_preserves_neighbors(uint16 flags, uint256 word, uint48 cursor, bool human) public {
        h.seedRng(flags, word, cursor, human);
        uint48 oldWrite = h.writeBuffer();
        h.swap();
        uint16 expected = (flags ^ (uint16(1) << 12)) & ~((uint16(1) << 8) | (uint16(1) << 15));
        assertEq(h.flags(), expected);
        assertEq(h.writeBuffer(), oldWrite ^ 1);
        assertEq(h.readBuffer(), oldWrite);
        assertEq(h.cursor(), 0);
        assertFalse(h.humanDone());
        assertEq(h.wordAt(oldWrite), 0, "seal revokes publication before replacing payload");
    }
    function check_word_only_for_published_read(uint16 flags, uint256 word, uint48 tag) public {
        h.seedRng(flags, word, 0, false);
        uint48 read = uint48((flags >> 12) & 1) ^ 1;
        uint256 expected = tag == read && flags & (uint16(1) << 15) != 0 && word != 1 ? word : 0;
        assertEq(h.wordAt(tag), expected);
    }
    function check_nudge_count_preserves_request_and_selector(uint16 flags, uint16 count_) public {
        vm.assume(count_ <= 255);
        h.seedRng(flags, 2, 0, false);
        h.setNudges(count_);
        uint16 mask = uint16(0xFF);
        assertEq(h.flags(), (flags & ~mask) | count_);
        assertEq(h.nudges(), count_);
    }

}
