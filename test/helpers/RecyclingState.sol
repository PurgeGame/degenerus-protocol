// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {Vm} from "forge-std/Vm.sol";

/// @dev Authoritative fixture writes for the reusable word, with its physical read/write selector.
/// Layout numbers are pinned by the storage-layout oracle, not inferred from old mappings.
library RecyclingState {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    function seedDailyWord(address host, uint24 day, uint256 value) internal {
        uint256 shift = (day & 1) * 24;
        uint256 tags = uint256(vm.load(host, bytes32(uint256(34))));
        vm.store(host, bytes32(uint256(34)), bytes32((tags & ~(uint256(type(uint24).max) << shift)) | (uint256(day) << shift)));
        vm.store(host, keccak256(abi.encode(uint256(day & 1), uint256(10))), bytes32(value));
    }
    function dailyWord(address host, uint24 day) internal view returns (uint256) {
        uint256 tags = uint256(vm.load(host, bytes32(uint256(34))));
        if (day == 0 || uint24(tags >> ((day & 1) * 24)) != day) return 0;
        return uint256(vm.load(host, keccak256(abi.encode(uint256(day & 1), uint256(10)))));
    }
    function writeBuffer(address host) internal view returns (uint48) { return uint48((uint256(vm.load(host, bytes32(0))) >> 252) & 1); }
    function readBuffer(address host) internal view returns (uint48) { return writeBuffer(host) ^ 1; }
    function seedWriteBuffer(address host, uint48 buffer) internal {
        require(buffer < 2, "physical buffer fixture");
        uint256 state = uint256(vm.load(host, bytes32(0)));
        vm.store(host, bytes32(0), bytes32((state & ~(uint256(1) << 252)) | (uint256(buffer) << 252)));
    }
    function seedWord(address host, uint48 buffer, bytes32 value) internal {
        require(buffer < 2, "physical buffer fixture");
        vm.store(host, bytes32(uint256(3)), uint256(value) < 2 ? bytes32(uint256(1)) : value);
        seedWriteBuffer(host, buffer ^ 1);
        uint256 state = uint256(vm.load(host, bytes32(0)));
        state &= ~((uint256(1) << 248) | (uint256(1) << 254) | (uint256(1) << 255));
        if (uint256(value) > 1) state |= uint256(1) << 255;
        vm.store(host, bytes32(0), bytes32(state));
        uint256 cursor = uint256(vm.load(host, bytes32(uint256(56))));
        vm.store(host, bytes32(uint256(56)), bytes32(cursor & ~(uint256(0xff) << 104)));
    }
    function word(address host, uint48 buffer) internal view returns (uint256) {
        uint256 state = uint256(vm.load(host, bytes32(0)));
        if (buffer != readBuffer(host) || state & (uint256(1) << 255) == 0) return 0;
        return currentWord(host);
    }
    /// @dev Current word: physical sentinel 1 reports no delivered word.
    function currentWord(address host) internal view returns (uint256) {
        uint256 stored = uint256(vm.load(host, bytes32(uint256(3))));
        return stored == 1 ? 0 : stored;
    }
    function nudgeCount(address host) internal view returns (uint256) {
        uint256 state = uint256(vm.load(host, bytes32(0))) >> 240;
        return ((state >> 1) & 127) | (((state >> 9) & 3) << 7);
    }
    function seedNudges(address host, uint256 count) internal {
        require(count <= 256, "fixture nudge cap");
        uint256 state = uint256(vm.load(host, bytes32(0)));
        uint256 mask = ((uint256(127) << 1) | (uint256(3) << 9)) << 240;
        uint256 encoded = ((count & 127) << 1) | ((count >> 7) << 9);
        vm.store(host, bytes32(0), bytes32((state & ~mask) | (encoded << 240)));
    }
    function pending(address host, uint24 day) internal view returns (bytes32) {
        uint24 stamped = uint24(uint256(vm.load(host, bytes32(uint256(0)))) >> 224);
        return stamped == day && day != 0 ? vm.load(host, bytes32(uint256(7))) : bytes32(0);
    }
}
