// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {Vm} from "forge-std/Vm.sol";
import {GameSlots} from "../../helpers/GameSlots.sol";

/// @dev Raw reference for queue roots, normal pending lanes and packed logical future levels.
///      Slots come from GameSlots (pinned by StorageSlotPins); queue and bucket lanes hold
///      wallet IDs (wallet-table position; element 0 is never assigned).
library TicketQueueStorage {
    uint256 internal constant QUEUE = GameSlots.TICKET_QUEUE;
    uint256 internal constant MINT = GameSlots.WALLET_IDS; // Forward address-to-ID registry.
    uint256 internal constant OWNERS = GameSlots.WALLETS; // Wallet table; ID = position.
    uint256 internal constant PENDING = GameSlots.TICKET_PENDING;
    uint256 internal constant FUTURE = GameSlots.FAR_FUTURE_OWED;
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function queueKey(uint24 key) internal pure returns (uint24) {
        uint24 lvl = key & 0x3fffff;
        uint24 slots = key & 0x400000 != 0 ? 100 : 2;
        return (key & 0xc00000) | (lvl == 0 ? 0 : (lvl - 1) % slots + 1);
    }
    function ownerKey(uint24 lvl) internal pure returns (uint24) { return lvl; }
    function _id(address host, address player) private view returns (uint32) {
        return uint32(uint256(vm.load(host, keccak256(abi.encode(player, MINT)))));
    }
    function _shift(uint24 key) private pure returns (uint256) {
        return (key & 1) * 84 + (key & (uint24(1) << 23) != 0 ? 42 : 0);
    }
    function _pending(uint24, uint32 id) private pure returns (bytes32) {
        return keccak256(abi.encode(uint256(id), PENDING));
    }
    /// @dev Queue header: owner count in bits 0..31, occupying level tag in bits 32..55
    ///      (zero: the physical slot's own level).
    function _header(address host, uint24 physical) private view returns (uint256) {
        return uint256(vm.load(host, keccak256(abi.encode(uint256(physical), QUEUE))));
    }
    function _occupying(uint256 header, uint24 physical) private pure returns (uint24 occupying) {
        occupying = uint24(header >> 32);
        if (occupying == 0) occupying = physical & 0x3fffff;
    }
    function length(address host, uint24 key) internal view returns (uint256) {
        uint24 physical = queueKey(key);
        uint256 header = _header(host, physical);
        if (_occupying(header, physical) != (key & 0x3fffff)) return 0;
        return uint32(header);
    }
    /// @dev A raw jump models completed prior queues by consuming only their matching balances.
    function retireCompleted(address host, uint24 throughLevel) internal {
        for (uint24 physical = 1; physical <= 100; ++physical) {
            for (uint24 domain; domain < 3; ++domain) {
                uint24 flags = domain == 0 ? 0 : (domain == 1 ? uint24(1 << 23) : uint24(1 << 22));
                if (domain != 2 && physical > 2) continue;
                uint24 root = physical | flags;
                uint256 header = _header(host, root);
                uint24 occupying = _occupying(header, root);
                if (occupying > throughLevel) continue;
                uint24 key = occupying | flags;
                uint256 n = length(host, key);
                for (uint256 i; i < n; ++i) {
                    uint32 id = ownerIdAt(host, key, i);
                    if (owedById(host, key, id) != 0) setOwedById(host, key, id, 0);
                }
                vm.store(host, keccak256(abi.encode(uint256(root), QUEUE)), bytes32(header & ~uint256(type(uint32).max)));
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
            require(id != 0 && id < count, "invalid owner ID");
            uint256 ownerWord = _ownerWord(host, id);
            uint32 parent = uint32(ownerWord >> 160);
            if (parent == 0) {
                address player = address(uint160(ownerWord));
                require(player != address(0) && _id(host, player) == id, "wallet identity mismatch");
            } else {
                require(uint160(ownerWord) == 0 && parent < count, "invalid subaccount owner");
                uint256 parentWord = _ownerWord(host, parent);
                require(parentWord >> 160 == 0 && uint160(parentWord) != 0, "owner must be ordinary");
                require(_id(host, address(uint160(parentWord))) == parent, "owner identity mismatch");
            }
        }
    }
    function seed(address host, uint24 key, uint24 lvl, address player, uint80 value) internal returns (uint256 index) {
        uint32 id = _id(host, player);
        if (id == 0) {
            uint256 count = uint256(vm.load(host, bytes32(OWNERS)));
            if (count == 0) count = 1; // element 0 is never assigned
            require(count <= type(uint32).max);
            id = uint32(count);
            vm.store(host, bytes32(uint256(keccak256(abi.encode(OWNERS))) + count), bytes32(uint256(uint160(player))));
            vm.store(host, bytes32(OWNERS), bytes32(count + 1));
            bytes32 mintSlot = keccak256(abi.encode(player, MINT));
            vm.store(host, mintSlot, bytes32(uint256(id)));
        }
        setOwed(host, key, player, (uint80(id) << 48) | uint48(value));
        uint24 physical = queueKey(key);
        bytes32 queue = keccak256(abi.encode(uint256(physical), QUEUE));
        uint256 header = uint256(vm.load(host, queue));
        index = _occupying(header, physical) == lvl ? uint32(header) : 0;
        bytes32 slot = bytes32(uint256(keccak256(abi.encode(queue))) + index / 8);
        uint256 factor = 2 ** (32 * (index % 8));
        uint256 word = uint256(vm.load(host, slot));
        vm.store(host, slot, bytes32((word & ~(uint256(type(uint32).max) * factor)) | (uint256(id) * factor)));
        vm.store(host, queue, bytes32((index + 1) | (uint256(lvl) << 32)));
    }
    function owed(address host, uint24 key, address player) internal view returns (uint80) {
        return owedById(host, key, _id(host, player));
    }
    function owedById(address host, uint24 key, uint32 id) internal view returns (uint80) {
        if (id == 0) return 0;
        if (key & (uint24(1) << 22) != 0) {
            uint24 lvl = key & 0x3fffff;
            if (lvl == 0) return 0;
            uint24 physical = queueKey(key);
            if (_occupying(_header(host, physical), physical) != lvl) return 0;
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
        setOwedById(host, key, _id(host, player), value);
    }
    function setOwedById(address host, uint24 key, uint32 id, uint80 value) internal {
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
    function _ownerWord(address host, uint32 id) private view returns (uint256) {
        return uint256(vm.load(host, bytes32(uint256(keccak256(abi.encode(OWNERS))) + id)));
    }
    function ownerIdAt(address host, uint24 key, uint256 index) internal view returns (uint32 id) {
        require(index < length(host, key));
        bytes32 queue = keccak256(abi.encode(uint256(queueKey(key)), QUEUE));
        uint256 word = uint256(vm.load(host, bytes32(uint256(keccak256(abi.encode(queue))) + index / 8)));
        id = uint32(word >> (32 * (index % 8)));
        require(id != 0);
    }
    function ownerAt(address host, uint24 key, uint24, uint256 index) internal view returns (address) {
        uint256 word = _ownerWord(host, ownerIdAt(host, key, index));
        uint32 parent = uint32(word >> 160);
        return address(uint160(parent == 0 ? word : _ownerWord(host, parent)));
    }
}
