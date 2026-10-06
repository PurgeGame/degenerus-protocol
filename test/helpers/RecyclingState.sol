// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {Vm} from "forge-std/Vm.sol";
import {GameSlots} from "./GameSlots.sol";

/// @dev Authoritative fixture writes for the reusable word, with its physical read/write selector.
/// Slot numbers come from GameSlots (pinned by test/fuzz/StorageSlotPins.t.sol).
library RecyclingState {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    function seedDailyWord(address host, uint24 day, uint256 value) internal {
        uint256 shift = (day & 1) * 24;
        uint256 tags = uint256(vm.load(host, bytes32(GameSlots.RNG_DAY_TAGS)));
        vm.store(host, bytes32(GameSlots.RNG_DAY_TAGS), bytes32((tags & ~(uint256(type(uint24).max) << shift)) | (uint256(day) << shift)));
        vm.store(host, keccak256(abi.encode(uint256(day & 1), GameSlots.RNG_WORD_BY_DAY)), bytes32(value));
    }
    function dailyWord(address host, uint24 day) internal view returns (uint256) {
        uint256 tags = uint256(vm.load(host, bytes32(GameSlots.RNG_DAY_TAGS)));
        if (day == 0 || uint24(tags >> ((day & 1) * 24)) != day) return 0;
        return uint256(vm.load(host, keccak256(abi.encode(uint256(day & 1), GameSlots.RNG_WORD_BY_DAY))));
    }
    function writeBuffer(address host) internal view returns (uint48) { return uint48((uint256(vm.load(host, bytes32(GameSlots.RNG_FLAGS_AND_NUDGES))) >> 252) & 1); }
    function readBuffer(address host) internal view returns (uint48) { return writeBuffer(host) ^ 1; }
    function seedWriteBuffer(address host, uint48 buffer) internal {
        require(buffer < 2, "physical buffer fixture");
        uint256 state = uint256(vm.load(host, bytes32(GameSlots.RNG_FLAGS_AND_NUDGES)));
        vm.store(host, bytes32(GameSlots.RNG_FLAGS_AND_NUDGES), bytes32((state & ~(uint256(1) << 252)) | (uint256(buffer) << 252)));
    }
    function seedWord(address host, uint48 buffer, bytes32 value) internal {
        require(buffer < 2, "physical buffer fixture");
        // Sealing the current write buffer latches its queue counts, as `_swapRngBuffers` does.
        if (writeBuffer(host) == buffer) latchQueueCounts(host);
        vm.store(host, bytes32(GameSlots.RNG_WORD_CURRENT), uint256(value) < 2 ? bytes32(uint256(1)) : value);
        seedWriteBuffer(host, buffer ^ 1);
        uint256 state = uint256(vm.load(host, bytes32(GameSlots.RNG_FLAGS_AND_NUDGES)));
        state &= ~((uint256(1) << 248) | (uint256(1) << 254) | (uint256(1) << 255));
        if (uint256(value) > 1) state |= uint256(1) << 255;
        vm.store(host, bytes32(GameSlots.RNG_FLAGS_AND_NUDGES), bytes32(state));
        uint256 cursor = uint256(vm.load(host, bytes32(GameSlots.HUMAN_READ_COMPLETE)));
        vm.store(host, bytes32(GameSlots.HUMAN_READ_COMPLETE), bytes32(cursor & ~(uint256(0xff) << (GameSlots.HUMAN_READ_COMPLETE_OFFSET * 8))));
    }
    /// @dev The seal's queue bookkeeping: the box and bet write counts (lootboxRngPacked bits
    ///      120..151 / 152..183) become the read lengths, the write counts restart at zero and
    ///      both read cursors restart.
    function latchQueueCounts(address host) internal {
        uint256 mask32 = type(uint32).max;
        uint256 lr = uint256(vm.load(host, bytes32(GameSlots.LOOTBOX_RNG_PACKED)));
        uint256 boxes = (lr >> 120) & mask32;
        uint256 bets = (lr >> 152) & mask32;
        vm.store(host, bytes32(GameSlots.LOOTBOX_RNG_PACKED), bytes32(lr & ~((mask32 << 120) | (mask32 << 152))));
        uint256 b = uint256(vm.load(host, bytes32(GameSlots.BOX_CURSOR)));
        b &= ~((uint256(type(uint48).max) << (GameSlots.BOX_CURSOR_OFFSET * 8))
            | (mask32 << (GameSlots.BOX_READ_COUNT_OFFSET * 8)));
        vm.store(host, bytes32(GameSlots.BOX_CURSOR), bytes32(b | (boxes << (GameSlots.BOX_READ_COUNT_OFFSET * 8))));
        uint256 d = uint256(vm.load(host, bytes32(GameSlots.DEGENERETTE_CURSOR)));
        d &= ~((uint256(type(uint48).max) << (GameSlots.DEGENERETTE_CURSOR_OFFSET * 8))
            | (mask32 << (GameSlots.DEGENERETTE_READ_COUNT_OFFSET * 8)));
        vm.store(host, bytes32(GameSlots.DEGENERETTE_CURSOR), bytes32(d | (bets << (GameSlots.DEGENERETTE_READ_COUNT_OFFSET * 8))));
    }
    /// @dev Box entries / bets queued in `buffer` (write count or sealed read count).
    function boxCount(address host, uint48 buffer) internal view returns (uint256) {
        if (buffer == writeBuffer(host)) return (uint256(vm.load(host, bytes32(GameSlots.LOOTBOX_RNG_PACKED))) >> 120) & type(uint32).max;
        return (uint256(vm.load(host, bytes32(GameSlots.BOX_READ_COUNT))) >> (GameSlots.BOX_READ_COUNT_OFFSET * 8)) & type(uint32).max;
    }
    function betCount(address host, uint48 buffer) internal view returns (uint256) {
        if (buffer == writeBuffer(host)) return (uint256(vm.load(host, bytes32(GameSlots.LOOTBOX_RNG_PACKED))) >> 152) & type(uint32).max;
        return (uint256(vm.load(host, bytes32(GameSlots.DEGENERETTE_READ_COUNT))) >> (GameSlots.DEGENERETTE_READ_COUNT_OFFSET * 8)) & type(uint32).max;
    }
    /// @dev Stored box entry `position` of `buffer`.
    function boxEntry(address host, uint48 buffer, uint256 position) internal view returns (uint256) {
        bytes32 data = keccak256(abi.encode(keccak256(abi.encode(uint256(buffer), GameSlots.BOX_QUEUE))));
        return uint256(vm.load(host, bytes32(uint256(data) + position)));
    }
    function word(address host, uint48 buffer) internal view returns (uint256) {
        uint256 state = uint256(vm.load(host, bytes32(GameSlots.RNG_FLAGS_AND_NUDGES)));
        if (buffer != readBuffer(host) || state & (uint256(1) << 255) == 0) return 0;
        return currentWord(host);
    }
    /// @dev Current word: physical sentinel 1 reports no delivered word.
    function currentWord(address host) internal view returns (uint256) {
        uint256 stored = uint256(vm.load(host, bytes32(GameSlots.RNG_WORD_CURRENT)));
        return stored == 1 ? 0 : stored;
    }
    function nudgeCount(address host) internal view returns (uint256) {
        uint256 state = uint256(vm.load(host, bytes32(GameSlots.RNG_FLAGS_AND_NUDGES))) >> 240;
        return state & 0xFF;
    }
    function seedNudges(address host, uint256 count) internal {
        require(count <= 255, "fixture nudge cap");
        uint256 state = uint256(vm.load(host, bytes32(GameSlots.RNG_FLAGS_AND_NUDGES)));
        uint256 mask = uint256(0xFF) << 240;
        vm.store(host, bytes32(GameSlots.RNG_FLAGS_AND_NUDGES), bytes32((state & ~mask) | (count << 240)));
    }

}
