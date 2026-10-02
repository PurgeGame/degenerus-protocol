// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";

/// @dev Raw-slot reference model. Roots are pinned against the inherited layout in TicketQueueCodec.
///      Arithmetic word/lane indexing is independent of the production assembly helpers.
library TicketQueueStorage {
    uint256 internal constant QUEUE = 12;
    uint256 internal constant OWED = 13;
    uint256 internal constant OWNERS = 67;
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant QUEUE_LEVELS = 78;

    function queueKey(uint24 key) internal pure returns (uint24) {
        uint24 lvl = key & 0x3fffff;
        return (key & 0xc00000) | (lvl == 0 ? 0 : (lvl - 1) % 100 + 1);
    }
    function ownerKey(uint24 lvl) internal pure returns (uint24) {
        return lvl;
    }
    function length(address host, uint24 key) internal view returns (uint256) {
        uint24 lvl = key & 0x3fffff;
        uint24 occupying = uint24(uint256(vm.load(host, keccak256(abi.encode(uint256(queueKey(key)), QUEUE_LEVELS)))));
        if (occupying == 0) occupying = queueKey(key) & 0x3fffff;
        if (occupying != lvl) return 0;
        return uint256(vm.load(host, keccak256(abi.encode(uint256(queueKey(key)), QUEUE))));
    }
    /// @dev Test fixtures that jump over levels must consume their completed queues,
    ///      just as actual advancement does, before seeding a new future horizon.
    function retireCompleted(address host, uint24 throughLevel) internal {
        for (uint24 physical = 1; physical <= 100; ++physical) {
            for (uint24 domain; domain < 3; ++domain) {
                uint24 flags = domain == 0 ? 0 : (domain == 1 ? uint24(1 << 23) : uint24(1 << 22));
                uint24 root = physical | flags;
                uint24 occupying = uint24(uint256(vm.load(host, keccak256(abi.encode(uint256(root), QUEUE_LEVELS)))));
                if (occupying == 0) occupying = physical;
                if (occupying > throughLevel) continue;
                uint24 key = occupying | flags;
                bytes32 queue = keccak256(abi.encode(uint256(root), QUEUE));
                uint256 n = length(host, key);
                bytes32 owners = keccak256(abi.encode(uint256(occupying), OWNERS));
                uint256 records = uint256(keccak256(abi.encode(owners)));
                for (uint256 i; i < n; ++i) {
                    uint256 word = uint256(vm.load(host, bytes32(uint256(keccak256(abi.encode(queue))) + i / 8)));
                    uint256 pos = (word >> (32 * (i % 8))) & type(uint32).max;
                    require(pos != 0, "retiring zero queue lane");
                    bytes32 record = bytes32(records + pos - 1);
                    vm.store(host, record, bytes32(uint256(uint160(uint256(vm.load(host, record))))));
                }
                vm.store(host, queue, bytes32(0));
            }
        }
    }

    function assertQueue(address host, uint24 key) internal view {
        uint24 lvl = key & ((uint24(1) << 22) - 1);
        bytes32 queue = keccak256(abi.encode(uint256(queueKey(key)), QUEUE));
        bytes32 owners = keccak256(abi.encode(uint256(ownerKey(lvl)), OWNERS));
        uint256 count = uint256(vm.load(host, owners));
        uint256 n = length(host, key);
        for (uint256 i; i < n; ++i) {
            uint256 word = uint256(vm.load(host, bytes32(uint256(keccak256(abi.encode(queue))) + i / 8)));
            uint256 pos = (word / (2 ** (32 * (i % 8)))) % (2 ** 32);
            require(pos != 0 && pos <= count, "queue position outside registry");
            uint256 record = uint256(vm.load(host, bytes32(uint256(keccak256(abi.encode(owners))) + pos - 1)));
            address player = address(uint160(record));
            require(player != address(0), "queue owner is zero");
            uint80 packed = uint80(record >> 160);
            if (packed != 0) {
                require(uint32(packed >> 48) == pos, "owed position mismatch");
                bytes32 locator = keccak256(abi.encode(player, keccak256(abi.encode(uint256(key), OWED))));
                require(uint256(vm.load(host, locator)) == pos, "live queue locator mismatch");
            }
        }
    }

    function seed(address host, uint24 key, uint24 lvl, address player, uint80 owed)
        internal returns (uint256 index)
    {
        bytes32 owners = keccak256(abi.encode(uint256(ownerKey(lvl)), OWNERS));
        bytes32 queue = keccak256(abi.encode(uint256(queueKey(key)), QUEUE));
        bytes32 tag = keccak256(abi.encode(uint256(queueKey(key)), QUEUE_LEVELS));
        uint24 occupying = uint24(uint256(vm.load(host, tag)));
        if (occupying == 0) occupying = queueKey(key) & 0x3fffff;
        // A raw fixture may jump over completed centuries. Seed only this level's
        // lanes, rather than inheriting another level's old physical length.
        if (occupying != lvl) vm.store(host, queue, bytes32(0));
        vm.store(host, tag, bytes32(uint256(lvl)));
        uint256 count = uint256(vm.load(host, owners));
        // Keep registry index zero out of worst-case fixtures.
        if (count == 0) {
            vm.store(host, keccak256(abi.encode(owners)), bytes32(uint256(1)));
            count = 1;
        }
        require(count < uint256(type(uint32).max) - 1);
        uint80 packed = uint80(((count + 1) << 48) | uint48(owed));
        vm.store(host, bytes32(uint256(keccak256(abi.encode(owners))) + count),
            bytes32(uint256(uint160(player)) | (uint256(packed) << 160)));
        vm.store(host, owners, bytes32(count + 1));
        index = uint256(vm.load(host, queue));
        bytes32 slot = bytes32(uint256(keccak256(abi.encode(queue))) + index / 8);
        uint256 factor = 2 ** (32 * (index % 8));
        uint256 word = uint256(vm.load(host, slot));
        word = (word & ~(uint256(type(uint32).max) * factor)) | ((count + 1) * factor);
        vm.store(host, slot, bytes32(word));
        vm.store(host, queue, bytes32(index + 1));
        bytes32 owedSlot = keccak256(abi.encode(player, keccak256(abi.encode(uint256(key), OWED))));
        vm.store(host, owedSlot, bytes32(count + 1));
    }

    function owed(address host, uint24 key, address player) internal view returns (uint80) {
        bytes32 locator = keccak256(abi.encode(player, keccak256(abi.encode(uint256(key), OWED))));
        uint256 pos = uint32(uint256(vm.load(host, locator)));
        if (pos == 0) return 0;
        uint24 lvl = key & ((uint24(1) << 22) - 1);
        bytes32 owners = keccak256(abi.encode(uint256(ownerKey(lvl)), OWNERS));
        return uint80(uint256(vm.load(host, bytes32(uint256(keccak256(abi.encode(owners))) + pos - 1))) >> 160);
    }

    function setOwed(address host, uint24 key, address player, uint80 value) internal {
        bytes32 locator = keccak256(abi.encode(player, keccak256(abi.encode(uint256(key), OWED))));
        uint256 pos = uint32(uint256(vm.load(host, locator)));
        require(pos != 0);
        uint24 lvl = key & ((uint24(1) << 22) - 1);
        bytes32 owners = keccak256(abi.encode(uint256(ownerKey(lvl)), OWNERS));
        bytes32 slot = bytes32(uint256(keccak256(abi.encode(owners))) + pos - 1);
        uint256 owner = uint160(uint256(vm.load(host, slot)));
        vm.store(host, slot, bytes32(owner | (uint256(value) << 160)));
    }

    function ownerAt(address host, uint24 key, uint24 lvl, uint256 index) internal view returns (address) {
        bytes32 queue = keccak256(abi.encode(uint256(queueKey(key)), QUEUE));
        require(index < uint256(vm.load(host, queue)));
        uint256 word = uint256(vm.load(host, bytes32(uint256(keccak256(abi.encode(queue))) + index / 8)));
        uint256 pos = (word / (2 ** (32 * (index % 8)))) % (2 ** 32);
        require(pos != 0);
        bytes32 owners = keccak256(abi.encode(uint256(ownerKey(lvl)), OWNERS));
        return address(uint160(uint256(vm.load(host, bytes32(uint256(keccak256(abi.encode(owners))) + pos - 1)))));
    }
}
