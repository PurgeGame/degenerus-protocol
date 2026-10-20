// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";

/// @dev Raw layout fixture, independently addressed from the production helpers.
library CoinflipStorage {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function ringSlot(uint32 id, uint24 page) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(uint256(id), uint256(0)))) + page % 15);
    }

    function overflowSlot(uint32 id, uint24 page) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(page), keccak256(abi.encode(uint256(id), uint256(9)))));
    }

    function read(address target, uint32 id, uint24 day) internal view returns (uint256) {
        uint24 page = day / 7;
        uint256 word = uint256(VM.load(target, ringSlot(id, page)));
        if (uint24(word >> 224) != page + 1) word = uint256(VM.load(target, overflowSlot(id, page)));
        if (uint24(word >> 224) != page + 1) return 0;
        return uint32(word >> ((day % 7) * 32));
    }

    /// @dev Arbitrary-order fixture writes retain collisions in overflow. This does not
    ///      exercise production reclamation; codec and differential tests do that separately.
    function set(address target, uint32 id, uint24 day, uint256 amount) internal {
        uint24 page = day / 7;
        bytes32 slot = ringSlot(id, page);
        uint256 word = uint256(VM.load(target, slot));
        if (word != 0 && uint24(word >> 224) != page + 1) {
            VM.store(target, slot, bytes32((word & type(uint248).max) | (uint256(0x80 | (page & 127)) << 248)));
            slot = overflowSlot(id, page);
            word = uint256(VM.load(target, slot));
        }
        if (uint24(word >> 224) != page + 1) word = uint256(page + 1) << 224;
        uint256 shift = (day % 7) * 32;
        uint256 value = amount > type(uint32).max ? type(uint32).max : amount;
        VM.store(target, slot, bytes32((word & ~(uint256(type(uint32).max) << shift)) | (value << shift)));
    }
}
