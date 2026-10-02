// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @dev Adapt current seeded entitlements to the immutable historical reference runtimes.
///      Sparse IDs are copied only for queued wallets; never scan the lifetime registry.
abstract contract LegacyTicketOwnerReference is DegenerusGameStorage {
    function installLegacyOwners(uint24 key, uint24 lvl) external {
        uint256 root = uint256(keccak256(abi.encode(lvl, uint256(67))));
        uint256 base = uint256(keccak256(abi.encode(root)));
        uint256 len = ticketOwners.length;
        assembly ("memory-safe") { sstore(root, len) }
        uint256[] storage q = ticketQueue[_ticketQueueStorageKey(key)];
        for (uint256 i; i < q.length; ++i) {
            uint32 id = _tqPositionAt(q, i);
            if (id == 0) continue; // Preserve the deliberately malformed zero-lane witness.
            uint256 record = _entryRecord(key, id);
            uint256 slot = base + id - 1;
            assembly ("memory-safe") { sstore(slot, record) }
        }
    }

    function logicalDrainState(uint24 key, uint24 lvl, bool legacy) external view returns (bytes32 digest) {
        digest = keccak256(abi.encode(ticketSeats, ticketRound));
        uint256 legacyBase = uint256(keccak256(abi.encode(keccak256(abi.encode(lvl, uint256(67))))));
        uint256[] storage q = ticketQueue[_ticketQueueStorageKey(key)];
        for (uint256 i; i < q.length; ++i) {
            uint32 id = _tqPositionAt(q, i);
            uint80 packed;
            if (legacy) {
                uint256 slot = legacyBase + id - 1;
                assembly ("memory-safe") { packed := shr(160, sload(slot)) }
            } else packed = _entryPacked(key, id);
            // Exhausted legacy records keep their ID; current lanes synthesize zero.
            digest = keccak256(abi.encode(digest, id, packed & ((uint80(1) << 41) - 1)));
        }
    }

    function logicalBuckets(uint24 lvl, bool legacy) external view returns (bytes32 digest) {
        uint256 root = uint256(keccak256(abi.encode(uint256(legacy ? lvl : lvl & 1), uint256(8))));
        for (uint256 trait; trait < 256; ++trait) {
            uint256 slot = root + trait;
            uint256 header;
            assembly ("memory-safe") { header := sload(slot) }
            uint256 count = legacy ? header : uint32(header);
            digest = keccak256(abi.encode(digest, trait, count));
            uint256 base = uint256(keccak256(abi.encode(slot)));
            for (uint256 i; i < (count + 7) / 8; ++i) {
                uint256 word;
                if (!legacy && i == count / 8) word = header >> 32;
                else { uint256 at = base + i; assembly ("memory-safe") { word := sload(at) } }
                if (i == count / 8 && count % 8 != 0) word &= (uint256(1) << (32 * (count % 8))) - 1;
                digest = keccak256(abi.encode(digest, word));
            }
        }
    }
}
