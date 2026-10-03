// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {Vm} from "forge-std/Vm.sol";

/// @dev Raw reference for queue roots, normal pending lanes and packed logical future levels.
///      Slots are attested against inherited production storage in TicketQueueCodec.
library TicketQueueStorage {
    uint256 internal constant QUEUE = 12;
    uint256 internal constant OWED = 13; // Permanent wallet-to-ID lookup.
    uint256 internal constant OWNERS = 67;
    uint256 internal constant QUEUE_LEVELS = 77;
    uint256 internal constant PENDING = 78;
    uint256 internal constant FUTURE = 81;
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function queueKey(uint24 key) internal pure returns (uint24) {
        uint24 lvl = key & 0x3fffff;
        uint24 slots = key & 0x400000 != 0 ? 100 : 2;
        return (key & 0xc00000) | (lvl == 0 ? 0 : (lvl - 1) % slots + 1);
    }
    function ownerKey(uint24 lvl) internal pure returns (uint24) { return lvl; }
    function _id(address host, address player) private view returns (uint32) {
        return uint32(uint256(vm.load(host, keccak256(abi.encode(player, OWED)))));
    }
    function _shift(uint24 key) private pure returns (uint256) {
        return (key & 1) * 84 + (key & (uint24(1) << 23) != 0 ? 42 : 0);
    }
    function _pending(uint24, uint32 id) private pure returns (bytes32) {
        return keccak256(abi.encode(uint256(id), PENDING));
    }
    function length(address host, uint24 key) internal view returns (uint256) {
        uint24 physical = queueKey(key);
        uint24 occupying = uint24(uint256(vm.load(host, keccak256(abi.encode(uint256(physical), QUEUE_LEVELS)))));
        if (occupying == 0) occupying = physical & 0x3fffff;
        if (occupying != (key & 0x3fffff)) return 0;
        return uint256(vm.load(host, keccak256(abi.encode(uint256(physical), QUEUE))));
    }
    /// @dev A raw jump models completed prior queues by consuming only their matching balances.
    function retireCompleted(address host, uint24 throughLevel) internal {
        for (uint24 physical = 1; physical <= 100; ++physical) {
            for (uint24 domain; domain < 3; ++domain) {
                uint24 flags = domain == 0 ? 0 : (domain == 1 ? uint24(1 << 23) : uint24(1 << 22));
                if (domain != 2 && physical > 2) continue;
                uint24 root = physical | flags;
                uint24 occupying = uint24(uint256(vm.load(host, keccak256(abi.encode(uint256(root), QUEUE_LEVELS)))));
                if (occupying == 0) occupying = physical;
                if (occupying > throughLevel) continue;
                uint24 key = occupying | flags;
                uint256 n = length(host, key);
                for (uint256 i; i < n; ++i) {
                    address player = ownerAt(host, key, occupying, i);
                    if (owed(host, key, player) != 0) setOwed(host, key, player, 0);
                }
                vm.store(host, keccak256(abi.encode(uint256(root), QUEUE)), bytes32(0));
            }
        }
    }
    function assertQueue(address host, uint24 key) internal view {
        uint256 n = length(host, key);
        uint256 count = uint256(vm.load(host, bytes32(OWNERS)));
        bytes32 queue = keccak256(abi.encode(uint256(queueKey(key)), QUEUE));
        for (uint256 i; i < n; ++i) {
            uint256 word = uint256(vm.load(host, bytes32(uint256(keccak256(abi.encode(queue))) + i / 8)));
            uint32 id = uint32(word / (2 ** (32 * (i % 8))));
            require(id != 0 && id <= count, "invalid owner ID");
            address player = address(uint160(uint256(vm.load(host, bytes32(uint256(keccak256(abi.encode(OWNERS))) + id - 1)))));
            require(player != address(0) && _id(host, player) == id, "identity mismatch");
        }
    }
    function seed(address host, uint24 key, uint24 lvl, address player, uint80 value) internal returns (uint256 index) {
        uint32 id = _id(host, player);
        if (id == 0) {
            uint256 count = uint256(vm.load(host, bytes32(OWNERS)));
            if (count == 0) {
                vm.store(host, keccak256(abi.encode(OWNERS)), bytes32(uint256(1)));
                vm.store(host, keccak256(abi.encode(address(1), OWED)), bytes32(uint256(1)));
                count = 1;
            }
            require(count < type(uint32).max);
            id = uint32(count + 1);
            vm.store(host, bytes32(uint256(keccak256(abi.encode(OWNERS))) + count), bytes32(uint256(uint160(player))));
            vm.store(host, bytes32(OWNERS), bytes32(uint256(id)));
            vm.store(host, keccak256(abi.encode(player, OWED)), bytes32(uint256(id)));
        }
        setOwed(host, key, player, (uint80(id) << 48) | uint48(value));
        uint24 physical = queueKey(key);
        bytes32 queue = keccak256(abi.encode(uint256(physical), QUEUE));
        bytes32 tag = keccak256(abi.encode(uint256(physical), QUEUE_LEVELS));
        uint24 occupying = uint24(uint256(vm.load(host, tag)));
        if (occupying == 0) occupying = physical & 0x3fffff;
        if (occupying != lvl) vm.store(host, queue, bytes32(0));
        vm.store(host, tag, bytes32(uint256(lvl)));
        index = uint256(vm.load(host, queue));
        bytes32 slot = bytes32(uint256(keccak256(abi.encode(queue))) + index / 8);
        uint256 factor = 2 ** (32 * (index % 8));
        uint256 word = uint256(vm.load(host, slot));
        vm.store(host, slot, bytes32((word & ~(uint256(type(uint32).max) * factor)) | (uint256(id) * factor)));
        vm.store(host, queue, bytes32(index + 1));
    }
    function owed(address host, uint24 key, address player) internal view returns (uint80) {
        uint32 id = _id(host, player);
        if (id == 0) return 0;
        if (key & (uint24(1) << 22) != 0) {
            uint24 lvl = key & 0x3fffff;
            if (lvl == 0) return 0;
            uint24 physical = queueKey(key);
            uint24 occupying = uint24(uint256(vm.load(host, keccak256(abi.encode(uint256(physical), QUEUE_LEVELS)))));
            if (occupying == 0) occupying = physical & 0x3fffff;
            if (occupying != lvl) return 0;
            uint256 position = (lvl - 1) % 100;
            uint256 lane = uint32(uint256(vm.load(host, _future(key, id))) >> ((position & 7) * 32));
            return lane & 0x80000000 == 0 ? 0 : (uint80(id) << 48)
                | uint80((lane & 0x3fffffff) << 8) | uint80((lane & 0x40000000) << 10);
        }
        uint256 word = uint256(vm.load(host, _pending(key, id)));
        uint256 shift = _shift(key);
        if (((word >> (168 + (key & 1) * 24)) & 0xffffff) != (key & 0x3fffff)) return 0;
        uint256 lane = (word >> shift) & ((uint256(1) << 42) - 1);
        if (lane & (uint256(1) << 41) == 0) return 0;
        return (uint80(id) << 48) | uint80(lane & ((uint256(1) << 41) - 1));
    }
    function _future(uint24 key, uint32 id) private pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(uint256(id), FUTURE))) + (((key & 0x3fffff) - 1) % 100) / 8);
    }
    function setOwed(address host, uint24 key, address player, uint80 value) internal {
        uint32 id = _id(host, player);
        require(id != 0);
        if (key & (uint24(1) << 22) != 0) {
            require(uint8(value) == 0);
            bytes32 target = _future(key, id);
            uint256 offset = ((((key & 0x3fffff) - 1) % 100) & 7) * 32;
            uint256 prior = uint256(vm.load(host, target));
            uint256 count = uint32(value >> 8);
            if (count > 0x3fffffff) count = 0x3fffffff;
            uint256 lane = value == 0 ? 0 : 0x80000000 | count | ((uint256(value) >> 10) & 0x40000000);
            vm.store(host, target, bytes32((prior & ~(uint256(type(uint32).max) << offset)) | (lane << offset)));
            return;
        }
        bytes32 slot = _pending(key, id);
        uint256 shift = _shift(key);
        uint256 tagShift = 168 + (key & 1) * 24;
        uint256 tagMask = uint256(0xffffff) << tagShift;
        uint256 pairMask = ((uint256(1) << 84) - 1) << ((key & 1) * 84);
        uint256 prior = uint256(vm.load(host, slot));
        bool matches = ((prior >> tagShift) & 0xffffff) == (key & 0x3fffff);
        if (!matches && value == 0) return;
        require(matches || prior & pairMask == 0, "live near parity");
        uint256 lane = value == 0 ? 0 : (uint256(value) & ((uint256(1) << 41) - 1)) | (uint256(1) << 41);
        uint256 mask = (((uint256(1) << 42) - 1) << shift) | tagMask;
        uint256 next = (prior & ~mask) | (lane << shift) | (uint256(1) << 255);
        if (next & pairMask != 0) next |= uint256(key & 0x3fffff) << tagShift;
        vm.store(host, slot, bytes32(next));
    }
    function ownerAt(address host, uint24 key, uint24, uint256 index) internal view returns (address) {
        require(index < length(host, key));
        bytes32 queue = keccak256(abi.encode(uint256(queueKey(key)), QUEUE));
        uint256 word = uint256(vm.load(host, bytes32(uint256(keccak256(abi.encode(queue))) + index / 8)));
        uint32 id = uint32(word / (2 ** (32 * (index % 8))));
        require(id != 0);
        return address(uint160(uint256(vm.load(host, bytes32(uint256(keccak256(abi.encode(OWNERS))) + id - 1)))));
    }
}
