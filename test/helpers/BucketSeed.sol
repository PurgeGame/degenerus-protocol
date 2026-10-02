// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @title BucketSeed — test-side seeding and decoding of the packed trait buckets
/// @notice Harnesses that extend a production module mix this in to seed
///         `lvlTraitEntry[lvl][trait]` the way the drains do: register the owner in
///         the global owner registry, then append packed lanes naming that position.
/// @dev Test-only. No contracts/*.sol is mutated.
abstract contract BucketSeed is DegenerusGameStorage {
    /// @dev Seed a queue owner's locator and positional owed field without weakening owner identity.
    function _seedOwedAt(uint24 key, address player, uint80 packed) internal {
        uint32 pos = ticketOwnerId[player];
        require(pos != 0 && (uint32(packed >> OWNER_IDX_SHIFT) == 0 || uint32(packed >> OWNER_IDX_SHIFT) == pos), "owner ID mismatch");
        _setEntryOwed(key, pos, packed);
    }

    /// @dev Resolve the stable owner index without creating another registry position.
    function _ownerIdxFor(uint24 lvl, address player) internal returns (uint256) {
        return uint256(_registerEntryOwner(player, lvl) >> OWNER_IDX_SHIFT) - 1;
    }

    /// @dev Append `n` occurrences of `player` to lvlTraitEntry[lvl][trait].
    function _seedBucket(uint24 lvl, uint8 trait, address player, uint256 n) internal {
        _setTicketBufferLevel(lvl);
        _bucketAppendRun(_traitBufferBase(lvl), trait, _ownerIdxFor(lvl, player), n, lvl);
    }

    /// @dev Queue `player` on key `rk` for level `lvl` owing `packedOwedRem` (owed << 8 | rem),
    ///      registered the way every production sink registers.
    function _seedQueued(uint24 rk, uint24 lvl, address player, uint80 packedOwedRem) internal {
        // Keep position zero out of the seeded set: a zero lane index makes every word store a
        // no-op and understates gas.
        if (ticketOwners.length == 0) _registerEntryOwner(address(1), lvl);
        uint80 ownerBits = _registerEntryOwner(player, lvl);
        _tqAppend(rk, uint32(ownerBits >> OWNER_IDX_SHIFT));
        _seedOwedAt(rk, player, ownerBits | packedOwedRem);
    }

    /// @dev Append `count` distinct, non-zero holders `base+1 .. base+count`, one occurrence each.
    function _seedBucketDistinct(uint24 lvl, uint8 trait, uint256 count, uint160 base) internal {
        for (uint256 i; i < count; ++i) {
            _seedBucket(lvl, trait, address(base + uint160(i + 1)), 1);
        }
    }

    /// @dev Occurrence count of the bucket.
    function _seedBucketLen(uint24 lvl, uint8 trait) internal view returns (uint256) {
        return _bucketLength(lvl, trait);
    }

    /// @dev Reset the bucket to empty (the length word alone gates every read).
    function _seedBucketClear(uint24 lvl, uint8 trait) internal {
        uint256 lanesSlot = _traitBufferBase(lvl) + trait;
        assembly ("memory-safe") {
            sstore(lanesSlot, 0)
        }
    }
}
